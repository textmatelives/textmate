#import "BundlesManager.h"
#import "BundleFetcher.h"
#import "BundleRegistry.h"
#import "BundleSpec.h"
#import <bundles/load.h>
#import "InstallBundleItems.h"
#import <OakAppKit/NSAlert Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <SoftwareUpdate/OakDownloadManager.h>
#import <bundles/locations.h>
#import <bundles/query.h> // set_index
#import <regexp/format_string.h>
#import <text/ctype.h>
#import <text/decode.h>
#import <ns/ns.h>
#import <io/path.h>
#import <io/move_path.h>
#import <io/entries.h>
#import <io/events.h>
#import <oak/debug.h>
#import <sys/stat.h>

NSString* const kUserDefaultsDisableBundleUpdatesKey       = @"disableBundleUpdates";
NSString* const kUserDefaultsLastBundleUpdateCheckKey      = @"lastBundleUpdateCheck";
NSString* const kUserDefaultsBundleUpdateFrequencyKey      = @"bundleUpdateFrequency";

static NSTimeInterval const kDefaultPollInterval = 3*60*60;
static char const* kBundleAttributeUpdated = "org.textmate.bundle.updated";

static NSString* SafeBasename (NSString* name)
{
	return [[name stringByReplacingOccurrencesOfString:@"/" withString:@":"] stringByReplacingOccurrencesOfString:@"." withString:@"_"];
}

@interface BundlesManager () <OakUserDefaultsObserver>
{
	NSBackgroundActivityScheduler* _updateBundleIndexScheduler;

	std::vector<std::string> bundlesPaths;
	std::string bundlesIndexPath;
	std::set<std::string> watchList;
	plist::cache_t cache;
}
@property (nonatomic) BOOL      autoUpdateBundles;

@property (nonatomic) BOOL      needsCreateBundlesIndex;
@property (nonatomic) BOOL      needsSaveBundlesIndex;

@property (nonatomic) NSArray<Bundle*>* bundles;

@property (nonatomic) NSString* installDirectory;
@end

@implementation BundlesManager
+ (instancetype)sharedInstance
{
	static BundlesManager* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if(self = [super init])
	{
		_installDirectory = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"TextMate/Managed"];

		// Migration: delete stale legacy caches. Harmless if absent.
		NSString* legacyRemoteIndex = [_installDirectory stringByAppendingPathComponent:@"Cache/org.textmate.updates.default"];
		NSString* legacyLocalIndex  = [_installDirectory stringByAppendingPathComponent:@"LocalIndex.plist"];
		[NSFileManager.defaultManager removeItemAtPath:legacyRemoteIndex error:nil];
		[NSFileManager.defaultManager removeItemAtPath:legacyLocalIndex  error:nil];

		[self userDefaultsDidChange:nil];
		OakObserveUserDefaults(self);
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:NSApp];
	}
	return self;
}

- (void)userDefaultsDidChange:(id)sender
{
	self.autoUpdateBundles = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableBundleUpdatesKey];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
	if(self.needsSaveBundlesIndex)
		[self saveBundlesIndex:self];
}

- (void)setAutoUpdateBundles:(BOOL)flag
{
	if(_autoUpdateBundles == flag)
		return;

	[_updateBundleIndexScheduler invalidate];
	_updateBundleIndexScheduler = nil;

	_autoUpdateBundles = flag;
	if(_autoUpdateBundles)
	{
		CGFloat updateFrequency = [NSUserDefaults.standardUserDefaults floatForKey:kUserDefaultsBundleUpdateFrequencyKey] ?: kDefaultPollInterval;

		_updateBundleIndexScheduler = [[NSBackgroundActivityScheduler alloc] initWithIdentifier:[NSString stringWithFormat:@"%@.%@", NSBundle.mainBundle.bundleIdentifier, @"UpdateBundleIndex"]];
		_updateBundleIndexScheduler.interval = updateFrequency;
		_updateBundleIndexScheduler.repeats  = YES;
		[_updateBundleIndexScheduler scheduleWithBlock:^(NSBackgroundActivityCompletionHandler completionHandler){
			os_activity_initiate("Update registered bundles", OS_ACTIVITY_FLAG_DEFAULT, ^(){
				[self updateRegisteredBundlesWithCallback:^{
					completionHandler(NSBackgroundActivityResultFinished);
				}];
			});
		}];
	}
}

- (void)ensureMandatoryBundlesOnDisk
{
	[BundleRegistry.sharedInstance ensureMandatoryBundlesOnDisk];
}

- (void)addBundleFromURL:(NSString*)url ref:(NSString*)ref name:(NSString*)name completion:(void(^)(NSString*, NSError*))completion
{
	NSString* owner = nil;
	NSString* repo  = nil;
	if(![BundleFetcher parseURL:url owner:&owner repo:&repo])
	{
		completion(nil, [NSError errorWithDomain:@"BundlesManager" code:1 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot parse URL: %@", url] }]);
		return;
	}

	NSString* resolvedRef  = ref.length ? ref : @"main";
	NSString* resolvedName = name.length ? name : [repo stringByReplacingOccurrencesOfString:@".tmbundle" withString:@""];

	// Stage: fetch to a temp dir, read info.plist for UUID, then register.
	NSURL* stagingURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] isDirectory:YES];
	NSUUID* placeholderUUID = [NSUUID UUID];

	BundleSpec* probe = [[BundleSpec alloc] initWithUUID:placeholderUUID name:resolvedName url:url ref:resolvedRef];
	if(!probe)
	{
		completion(nil, [NSError errorWithDomain:@"BundlesManager" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Could not construct bundle spec" }]);
		return;
	}

	// We don't know the real UUID until after fetch. BundleFetcher validates
	// UUID against the spec — we need a two-step: fetch into staging without
	// UUID check, read UUID, then rename+register.
	//
	// Simpler approach: resolve SHA, fetch codeload directly, extract into a
	// temp dir, read info.plist UUID, then install properly into Managed/Bundles
	// using the proper name.

	NSString* encodedRef = [resolvedRef stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
	NSString* codeloadURL = [NSString stringWithFormat:@"https://codeload.github.com/%@/%@/tar.gz/%@", owner, repo, encodedRef];

	NSError* mkerr;
	if(![NSFileManager.defaultManager createDirectoryAtURL:stagingURL withIntermediateDirectories:YES attributes:nil error:&mkerr])
	{
		completion(nil, mkerr);
		return;
	}

	NSTask* curl = [NSTask new];
	curl.launchPath = @"/bin/sh";
	curl.arguments = @[ @"-c", [NSString stringWithFormat:@"curl --silent --show-error --fail --location '%@' | /usr/bin/tar -zxmkC '%@' --strip-components 1 --disable-copyfile --exclude '._*'", codeloadURL, stagingURL.path] ];
	curl.terminationHandler = ^(NSTask* t){
		dispatch_async(dispatch_get_main_queue(), ^{
			if(t.terminationStatus != 0)
			{
				[NSFileManager.defaultManager removeItemAtURL:stagingURL error:nil];
				completion(nil, [NSError errorWithDomain:@"BundlesManager" code:t.terminationStatus userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fetch %@", codeloadURL] }]);
				return;
			}

			NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:[stagingURL.path stringByAppendingPathComponent:@"info.plist"]];
			NSString* uuidStr = info[@"uuid"];
			NSUUID* uuid = uuidStr ? [[NSUUID alloc] initWithUUIDString:uuidStr] : nil;
			if(!uuid)
			{
				[NSFileManager.defaultManager removeItemAtURL:stagingURL error:nil];
				completion(nil, [NSError errorWithDomain:@"BundlesManager" code:3 userInfo:@{ NSLocalizedDescriptionKey: @"Fetched archive has no valid info.plist uuid" }]);
				return;
			}

			NSString* finalName = info[@"name"] ?: resolvedName;
			NSString* bundlesDir = [self->_installDirectory stringByAppendingPathComponent:@"Bundles"];
			[NSFileManager.defaultManager createDirectoryAtPath:bundlesDir withIntermediateDirectories:YES attributes:nil error:nil];
			NSURL* destURL = [NSURL fileURLWithPath:[[bundlesDir stringByAppendingPathComponent:SafeBasename(finalName)] stringByAppendingPathExtension:@"tmbundle"] isDirectory:YES];

			NSError* mvErr;
			if([NSFileManager.defaultManager fileExistsAtPath:destURL.path])
			{
				if(![NSFileManager.defaultManager replaceItemAtURL:destURL withItemAtURL:stagingURL backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:nil error:&mvErr])
				{
					completion(nil, mvErr);
					return;
				}
			}
			else
			{
				if(![NSFileManager.defaultManager moveItemAtURL:stagingURL toURL:destURL error:&mvErr])
				{
					completion(nil, mvErr);
					return;
				}
			}

			BundleSpec* existing = [BundleRegistry.sharedInstance specForUUID:uuid];
			BundleSpec* spec = existing ?: [[BundleSpec alloc] initWithUUID:uuid name:finalName url:url ref:resolvedRef];
			if(existing)
			{
				spec.ref = resolvedRef;
			}
			spec.autoUpdate   = YES;
			spec.installedAt  = [NSDate date];

			// Resolve the actual SHA so installedSHA is meaningful.
			[BundleFetcher.sharedInstance resolveSHAForSpec:spec conditionalEtag:nil completion:^(BundleSHAResolution* resolution, NSError* resolveError){
				if(resolution.sha.length)
				{
					spec.installedSHA = resolution.sha;
					if(resolution.etag.length)
						spec.etag = resolution.etag;
				}
				else
				{
					// Ref is already a SHA, or resolve failed — fall back to ref.
					spec.installedSHA = resolvedRef;
				}

				if(existing)
					[BundleRegistry.sharedInstance updateSpec:spec];
				else
					[BundleRegistry.sharedInstance addSpec:spec];

				[self reloadPath:destURL.path recursive:YES];
				[self createBundlesIndex:self];
				self.bundles = [self bundlesByLoadingIndex];

				completion(spec.installedSHA, nil);
			}];
		});
	};

	NSError* launchErr;
	if(@available(macos 10.13, *))
	{
		if(![curl launchAndReturnError:&launchErr])
		{
			[NSFileManager.defaultManager removeItemAtURL:stagingURL error:nil];
			completion(nil, launchErr);
			return;
		}
	}
	else
	{
		@try { [curl launch]; }
		@catch(NSException* e)
		{
			[NSFileManager.defaultManager removeItemAtURL:stagingURL error:nil];
			completion(nil, [NSError errorWithDomain:@"BundlesManager" code:4 userInfo:@{ NSLocalizedDescriptionKey: e.reason ?: @"NSTask launch failed" }]);
			return;
		}
	}
}

- (void)checkForBundleUpdatesNowWithCompletion:(void(^)(void))completion
{
	[self updateRegisteredBundlesWithCallback:^{
		self.bundles = [self bundlesByLoadingIndex];
		if(completion)
			completion();
	}];
}

- (void)updateRegisteredBundlesWithCallback:(void(^)(void))completionHandler
{
	NSArray<BundleSpec*>* specs = BundleRegistry.sharedInstance.allSpecs;
	NSString* bundlesDir = [_installDirectory stringByAppendingPathComponent:@"Bundles"];

	NSError* error;
	if(![NSFileManager.defaultManager createDirectoryAtPath:bundlesDir withIntermediateDirectories:YES attributes:nil error:&error])
	{
		os_log_error(OS_LOG_DEFAULT, "Failed to create %{public}@: %{public}@", bundlesDir, error.localizedDescription);
		completionHandler();
		return;
	}

	[self processSpecs:specs index:0 bundlesDir:bundlesDir completion:completionHandler];
}

- (void)processSpecs:(NSArray<BundleSpec*>*)specs index:(NSUInteger)i bundlesDir:(NSString*)bundlesDir completion:(void(^)(void))completion
{
	if(i >= specs.count)
	{
		[NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:kUserDefaultsLastBundleUpdateCheckKey];
		completion();
		return;
	}

	BundleSpec* spec = specs[i];

	// User turned off updates for this bundle (unchecked in prefs or
	// disabled in the manifest). Do not fetch.
	if(!spec.autoUpdate)
	{
		[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
		return;
	}

	NSURL* destURL = [NSURL fileURLWithPath:[[bundlesDir stringByAppendingPathComponent:SafeBasename(spec.name)] stringByAppendingPathExtension:@"tmbundle"] isDirectory:YES];
	BOOL isInstalled = [NSFileManager.defaultManager fileExistsAtPath:destURL.path];

	// Respect developer symlinks (e.g. reset_bundles.sh). Never overwrite a
	// symlink with a fetched archive — user wants their working checkout.
	// lstat is required — attributesOfItemAtPath: follows symlinks.
	struct stat st;
	if(lstat(destURL.path.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode))
	{
		os_log(OS_LOG_DEFAULT, "Skipping symlinked bundle %{public}@", spec.name);
		[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
		return;
	}

	// Shortcut: pinned SHA already installed — nothing to do.
	if(spec.isPinnedToSHA && isInstalled && [spec.installedSHA isEqualToString:spec.ref])
	{
		[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
		return;
	}

	void(^installAt)(NSString*) = ^(NSString* sha){
		[BundleFetcher.sharedInstance fetchAndInstallSpec:spec intoURL:destURL completion:^(NSString* resolvedSHA, NSError* fetchError){
			if(fetchError)
			{
				os_log_error(OS_LOG_DEFAULT, "Failed to install %{public}@: %{public}@", spec.name, fetchError.localizedDescription);
			}
			else
			{
				spec.installedSHA = sha ?: resolvedSHA;
				spec.installedAt  = [NSDate date];
				[BundleRegistry.sharedInstance updateSpec:spec];
				os_log(OS_LOG_DEFAULT, "Installed %{public}@ @ %{public}@", spec.name, spec.installedSHA ?: @"(unknown)");
				[self reloadPath:destURL.path recursive:YES];
			}
			[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
		}];
	};

	// Pinned SHA but not installed (or installed at wrong SHA): fetch directly.
	if(spec.isPinnedToSHA)
	{
		installAt(spec.ref);
		return;
	}

	// Branch/tag: resolve current SHA first, then fetch only if changed or missing.
	[BundleFetcher.sharedInstance resolveSHAForSpec:spec conditionalEtag:spec.etag completion:^(BundleSHAResolution* resolution, NSError* err){
		if(err)
		{
			os_log_error(OS_LOG_DEFAULT, "SHA resolve failed for %{public}@: %{public}@", spec.name, err.localizedDescription);
			[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
			return;
		}

		if(resolution.etag.length)
		{
			spec.etag = resolution.etag;
			[BundleRegistry.sharedInstance updateSpec:spec];
		}

		if(resolution.notModified && isInstalled)
		{
			[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
			return;
		}

		NSString* newSHA = resolution.sha;
		if(newSHA && isInstalled && [newSHA isEqualToString:spec.installedSHA])
		{
			[self processSpecs:specs index:i+1 bundlesDir:bundlesDir completion:completion];
			return;
		}

		installAt(newSHA);
	}];
}

- (void)installBundleItemsAtPaths:(NSArray*)somePaths
{
	InstallBundleItems(somePaths);
}

- (BOOL)findBundleForInstall:(bundles::item_ptr*)res
{
	oak::uuid_t defaultBundle;

	std::string const personalBundleName = format_string::expand("${TM_FULLNAME/^(\\S+).*$/$1/}’s Bundle", std::map<std::string, std::string>{ { "TM_FULLNAME", path::passwd_entry()->pw_gecos ?: "John Doe" } });
	for(auto item : bundles::query(bundles::kFieldName, personalBundleName, scope::wildcard, bundles::kItemTypeBundle))
		defaultBundle = item->uuid();

	NSPopUpButton* bundleChooser = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[bundleChooser.menu removeAllItems];
	[bundleChooser.menu addItemWithTitle:@"Create new bundle…" action:NULL keyEquivalent:@""];
	[bundleChooser.menu addItem:[NSMenuItem separatorItem]];

	std::multimap<std::string, bundles::item_ptr, text::less_t> ordered;
	for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeBundle))
		ordered.emplace(item->name(), item);

	for(auto pair : ordered)
	{
		NSMenuItem* menuItem = [bundleChooser.menu addItemWithTitle:[NSString stringWithCxxString:pair.first] action:NULL keyEquivalent:@""];
		[menuItem setRepresentedObject:[NSString stringWithCxxString:to_s(pair.second->uuid())]];
		if(defaultBundle && defaultBundle == pair.second->uuid())
			[bundleChooser selectItem:menuItem];
	}

	[bundleChooser sizeToFit];
	NSRect frame = [bundleChooser frame];
	if(NSWidth(frame) > 200)
		[bundleChooser setFrameSize:NSMakeSize(200, NSHeight(frame))];

	NSAlert* alert = [NSAlert tmAlertWithMessageText:@"Select Bundle" informativeText:@"Select the bundle which should be used for the new item(s)." buttons:@"OK", @"Cancel", nil];
	[alert setAccessoryView:bundleChooser];
	if([alert runModal] == NSAlertFirstButtonReturn) // "OK"
	{
		if(NSString* bundleUUID = [[bundleChooser selectedItem] representedObject])
		{
			for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeBundle, to_s(bundleUUID)))
			{
				*res = item;
				return YES;
			}
		}
		else
		{
			NSAlert* alert        = [[NSAlert alloc] init];
			alert.messageText     = @"Creating bundles is not yet supported.";
			alert.informativeText = @"You can create a new bundle in the bundle editor via File → New (⌘N) and then repeat the previous action.";
			[alert addButtonWithTitle:@"OK"];
			[alert runModal];
		}
	}
	return NO;
}

- (NSProgress*)installBundles:(NSArray<Bundle*>*)someBundles completionHandler:(void(^)(NSArray<Bundle*>*))callback
{
	if(someBundles.count == 0)
		return callback(nil), nil;

	NSString* bundlesDirectory = [_installDirectory stringByAppendingPathComponent:@"Bundles"];
	NSError* error;
	if(![NSFileManager.defaultManager createDirectoryAtPath:bundlesDirectory withIntermediateDirectories:YES attributes:nil error:&error])
	{
		os_log_error(OS_LOG_DEFAULT, "Failed to create directory %{public}@: %{public}@", bundlesDirectory, error.localizedDescription);
		return callback(nil), nil;
	}

	NSProgress* progress = [NSProgress discreteProgressWithTotalUnitCount:someBundles.count];
	NSMutableArray<Bundle*>* installed = [NSMutableArray array];
	dispatch_group_t group = dispatch_group_create();

	for(Bundle* bundle in someBundles)
	{
		BundleSpec* spec = [BundleRegistry.sharedInstance specForUUID:bundle.identifier];
		if(!spec || !spec.url)
		{
			os_log_error(OS_LOG_DEFAULT, "installBundles: no registry spec for %{public}@", bundle.name);
			progress.completedUnitCount += 1;
			continue;
		}

		NSURL* destURL = [NSURL fileURLWithPath:[[bundlesDirectory stringByAppendingPathComponent:SafeBasename(spec.name)] stringByAppendingPathExtension:@"tmbundle"] isDirectory:YES];

		dispatch_group_enter(group);
		[BundleFetcher.sharedInstance fetchAndInstallSpec:spec intoURL:destURL completion:^(NSString* resolvedSHA, NSError* fetchError){
			progress.completedUnitCount += 1;
			if(fetchError)
			{
				os_log_error(OS_LOG_DEFAULT, "Failed to install %{public}@: %{public}@", spec.name, fetchError.localizedDescription);
			}
			else
			{
				spec.installedSHA = resolvedSHA;
				spec.installedAt  = [NSDate date];
				spec.autoUpdate   = YES;
				[BundleRegistry.sharedInstance updateSpec:spec];
				path::set_attr(destURL.path.fileSystemRepresentation, kBundleAttributeUpdated, to_s(resolvedSHA ?: @""));
				bundle.installed   = YES;
				bundle.path        = destURL.path;
				bundle.lastUpdated = spec.installedAt;
				[self reloadPath:destURL.path recursive:YES];
				[installed addObject:bundle];
			}
			dispatch_group_leave(group);
		}];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		[self createBundlesIndex:self];
		callback(installed);
	});
	return progress;
}

- (void)uninstallBundle:(Bundle*)bundle
{
	if(bundle.isMandatory)
	{
		os_log_error(OS_LOG_DEFAULT, "Refusing to uninstall mandatory bundle %{public}@", bundle.name);
		return;
	}

	bundle.installed = NO;
	if(bundle.path && ![NSFileManager.defaultManager removeItemAtPath:bundle.path error:nil])
		return;

	if(bundle.path)
		[self erasePath:bundle.path];

	bundle.path        = nil;
	bundle.lastUpdated = nil;

	// Keep the registry entry so the checkbox can re-enable it. Turn off
	// autoUpdate and clear the install marker so the poll respects the
	// user's off-state and a future re-install fetches fresh.
	BundleSpec* spec = [BundleRegistry.sharedInstance specForUUID:bundle.identifier];
	if(spec)
	{
		spec.autoUpdate   = NO;
		spec.installedSHA = nil;
		spec.installedAt  = nil;
		spec.etag         = nil;
		[BundleRegistry.sharedInstance updateSpec:spec];
	}
}

- (void)removeBundleSpec:(Bundle*)bundle
{
	[self uninstallBundle:bundle];
	[BundleRegistry.sharedInstance removeSpecForUUID:bundle.identifier];
	self.bundles = [self bundlesByLoadingIndex];
}

// ===============================================
// = Creating Bundle Index and Handling FSEvents =
// ===============================================

- (void)createBundlesIndex:(id)sender
{
	if(_needsCreateBundlesIndex == NO)
		return;
	_needsCreateBundlesIndex = NO;

	auto pair = create_bundle_index(bundlesPaths, cache);
	bundles::set_index(pair.first, pair.second);

	std::set<std::string> newWatchList;
	for(auto path : bundlesPaths)
		cache.copy_heads_for_path(path, std::inserter(newWatchList, newWatchList.end()));
	[self updateWatchList:newWatchList];
}

- (void)saveBundlesIndex:(id)sender
{
	cache.cleanup(bundlesPaths);
	if(cache.dirty())
	{
		cache.save_capnp(bundlesIndexPath);
		cache.set_dirty(false);
	}
	_needsSaveBundlesIndex = NO;
}

- (void)setNeedsCreateBundlesIndex:(BOOL)flag
{
	if(_needsCreateBundlesIndex != flag && (_needsCreateBundlesIndex = flag))
		[self performSelector:@selector(createBundlesIndex:) withObject:self afterDelay:0];
}

- (void)setNeedsSaveBundlesIndex:(BOOL)flag
{
	if(_needsSaveBundlesIndex != flag && (_needsSaveBundlesIndex = flag))
		[self performSelector:@selector(saveBundlesIndex:) withObject:self afterDelay:5];
}

- (void)setEventId:(uint64_t)anEventId forPath:(NSString*)aPath
{
	cache.set_event_id_for_path(anEventId, to_s(aPath));
	self.needsSaveBundlesIndex = YES;
}

- (void)updateWatchList:(std::set<std::string> const&)newWatchList
{
	struct callback_t : fs::event_callback_t
	{
		void set_replaying_history (bool flag, std::string const& observedPath, uint64_t eventId)
		{
			[BundlesManager.sharedInstance setEventId:eventId forPath:[NSString stringWithCxxString:observedPath]];
		}

		void did_change (std::string const& path, std::string const& observedPath, uint64_t eventId, bool recursive)
		{
			[BundlesManager.sharedInstance reloadPath:[NSString stringWithCxxString:path] recursive:recursive];
			[BundlesManager.sharedInstance setEventId:eventId forPath:[NSString stringWithCxxString:observedPath]];
		}
	};

	static callback_t callback;

	std::vector<std::string> pathsAdded, pathsRemoved;
	std::set_difference(watchList.begin(), watchList.end(), newWatchList.begin(), newWatchList.end(), back_inserter(pathsRemoved));
	std::set_difference(newWatchList.begin(), newWatchList.end(), watchList.begin(), watchList.end(), back_inserter(pathsAdded));

	watchList = newWatchList;

	for(auto path : pathsRemoved)
	{
		fs::unwatch(path, &callback);
	}

	for(auto path : pathsAdded)
	{
		fs::watch(path, &callback, cache.event_id_for_path(path) ?: FSEventsGetCurrentEventId(), 1);
	}
}

- (void)erasePath:(NSString*)aPath
{
	if(cache.erase(to_s(aPath)))
	{
		self.needsCreateBundlesIndex = YES;
		self.needsSaveBundlesIndex   = YES;
	}
}

- (void)reloadPath:(NSString*)aPath
{
	[self reloadPath:aPath recursive:NO];
}

- (void)reloadPath:(NSString*)aPath recursive:(BOOL)flag
{
	if(cache.reload(to_s(aPath), flag))
	{
		self.needsCreateBundlesIndex = YES;
		self.needsSaveBundlesIndex   = YES;
	}
}

namespace
{
	static std::string const kFieldChangedItems = "changed";
	static std::string const kFieldDeletedItems = "deleted";
	static std::string const kFieldMainMenu     = "mainMenu";

	static plist::dictionary_t prune_dictionary (plist::dictionary_t const& plist)
	{
		static auto const DesiredKeys = new std::set<std::string>{ bundles::kFieldName, bundles::kFieldKeyEquivalent, bundles::kFieldTabTrigger, bundles::kFieldScopeSelector, bundles::kFieldSemanticClass, bundles::kFieldContentMatch, bundles::kFieldGrammarFirstLineMatch, bundles::kFieldGrammarScope, bundles::kFieldGrammarInjectionSelector, bundles::kFieldDropExtension, bundles::kFieldGrammarExtension, bundles::kFieldSettingName, bundles::kFieldHideFromUser, bundles::kFieldIsDeleted, bundles::kFieldIsDisabled, bundles::kFieldRequiredItems, bundles::kFieldUUID, bundles::kFieldIsDelta, kFieldMainMenu, kFieldDeletedItems, kFieldChangedItems };

		plist::dictionary_t res;
		for(auto pair : plist)
		{
			if(DesiredKeys->find(pair.first) == DesiredKeys->end() && pair.first.find(bundles::kFieldSettingName) != 0)
				continue;

			if(pair.first == bundles::kFieldSettingName)
			{
				if(plist::dictionary_t const* dictionary = boost::get<plist::dictionary_t>(&pair.second))
				{
					plist::array_t settings;
					for(auto const& settingsPair : *dictionary)
						settings.push_back(settingsPair.first);
					res.emplace(pair.first, settings);
				}
			}
			else if(pair.first == kFieldChangedItems)
			{
				if(plist::dictionary_t const* dictionary = boost::get<plist::dictionary_t>(&pair.second))
					res.emplace(pair.first, prune_dictionary(*dictionary));
			}
			else
			{
				res.insert(pair);
			}
		}
		return res;
	}
}

- (void)moveAvianBundles
{
	NSFileManager* fm = NSFileManager.defaultManager;

	NSMutableArray* moves = [NSMutableArray array];
	NSMutableString* moveDescription = [NSMutableString string];

	for(NSString* path in NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask|NSLocalDomainMask, YES))
	{
		for(NSString* dir in @[ @"", @"Pristine Copy" ])
		{
			NSString* textMateFolder = [NSString pathWithComponents:@[ path, @"TextMate", dir ]];
			NSString* avianFolder    = [NSString pathWithComponents:@[ path, @"Avian", dir ]];
			NSString* src = [avianFolder stringByAppendingPathComponent:@"Bundles"];
			NSString* dst = [textMateFolder stringByAppendingPathComponent:@"Bundles"];

			if([fm fileExistsAtPath:src] == NO)
				continue;

			if([fm fileExistsAtPath:dst] == YES)
			{
				[moves addObject:@[ dst, [dst stringByAppendingString:@"-1.x"] ]];
				[moveDescription appendFormat:@"Rename “Bundles” at “%@” to “Bundles-1.x” (backup).\n", [textMateFolder stringByAbbreviatingWithTildeInPath]];
			}

			[moves addObject:@[ src, dst ]];
			[moveDescription appendFormat:@"Move “Bundles” at “%@” to “%@”.\n", [avianFolder stringByAbbreviatingWithTildeInPath], [textMateFolder stringByAbbreviatingWithTildeInPath]];
		}
	}

	if(moves.count == 0)
		return;

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle      = NSAlertStyleInformational;
	alert.messageText     = @"Move Bundles?";
	alert.informativeText = [NSString stringWithFormat:@"Bundles are no longer read from the “Avian” folder. Would you like to move the following items:\n\n%@", moveDescription];
	[alert addButtonWithTitle:@"Move Bundles"];
	[alert addButtonWithTitle:@"Cancel"];
	if([alert runModal] != NSAlertFirstButtonReturn)
		return;

	for(NSArray* move in moves)
	{
		NSError* err;

		NSString* dstFolder = [move.lastObject stringByDeletingLastPathComponent];
		if([fm fileExistsAtPath:dstFolder] || [fm createDirectoryAtPath:dstFolder withIntermediateDirectories:YES attributes:nil error:&err])
		{
			if([fm moveItemAtPath:move.firstObject toPath:move.lastObject error:&err])
				continue;
		}

		[[NSAlert alertWithError:err] runModal];
		break;
	}
}

- (void)loadBundlesIndex
{
	// LEGACY locations used by 2.0-beta.12.22 and earlier
	[self moveAvianBundles];

	for(auto path : bundles::locations())
		bundlesPaths.push_back(path::join(path, "Bundles"));
	bundlesIndexPath = path::join(path::home(), "Library/Caches/com.macromates.TextMate/BundlesIndex.binary");
	cache.set_content_filter(&prune_dictionary);

	// LEGACY bundle index used prior to 2.0-alpha.9467
	std::string const oldPath = path::join(path::home(), "Library/Caches/com.macromates.TextMate/BundlesIndex.plist");
	if(access(oldPath.c_str(), R_OK) == 0)
	{
		cache.load(oldPath);
		cache.save_capnp(bundlesIndexPath);
		unlink(oldPath.c_str());
	}
	else
	{
		cache.load_capnp(bundlesIndexPath);
	}

	_needsCreateBundlesIndex = YES;
	[self createBundlesIndex:self];
}

namespace
{
	// Walks the tmbundle directory for a minimal list of bundle items; used
	// only for populating the Bundle model's `grammars` array. The primary
	// bundle-item index lives elsewhere (Cap'n Proto cache at
	// BundlesIndex.binary driven by FSEvents).
	static NSArray<NSDictionary*>* bundle_item_infos (NSDictionary* info, NSString* bundlePath)
	{
		NSMutableArray<NSDictionary*>* items = [NSMutableArray array];
		NSString* syntaxesDir = [bundlePath stringByAppendingPathComponent:@"Syntaxes"];
		for(NSString* name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:syntaxesDir error:nil])
		{
			if(![name.pathExtension isEqualToString:@"tmLanguage"] && ![name.pathExtension isEqualToString:@"plist"])
				continue;
			NSDictionary* gram = [NSDictionary dictionaryWithContentsOfFile:[syntaxesDir stringByAppendingPathComponent:name]];
			if(!gram[@"uuid"])
				continue;
			NSMutableDictionary* d = [NSMutableDictionary dictionary];
			d[@"type"]           = @"grammar";
			d[@"uuid"]           = gram[@"uuid"];
			d[@"name"]           = gram[@"name"];
			d[@"scope"]          = gram[@"scopeName"];
			d[@"firstLineMatch"] = gram[@"firstLineMatch"];
			d[@"fileTypes"]      = gram[@"fileTypes"];
			[items addObject:d];
		}
		return items;
	}

	static NSArray<Bundle*>* BundlesFromRegistry (NSString* installDir, NSDictionary<NSUUID*, Bundle*>* cache = nil)
	{
		NSMutableDictionary<NSUUID*, Bundle*>* res = [NSMutableDictionary dictionary];
		NSString* bundlesDir = [installDir stringByAppendingPathComponent:@"Bundles"];

		for(BundleSpec* spec in BundleRegistry.sharedInstance.allSpecs)
		{
			Bundle* bundle = cache[spec.uuid] ?: [[Bundle alloc] initWithIdentifier:spec.uuid];
			bundle.name        = spec.name;
			bundle.mandatory   = (spec.origin == TMBundleOriginMandatory);
			bundle.recommended = (spec.origin == TMBundleOriginShipped);
			bundle.downloadURL = spec.url.length ? [NSURL URLWithString:spec.url] : nil;
			bundle.downloadLastUpdated = spec.installedAt;
			bundle.lastUpdated         = spec.installedAt;

			NSString* bundlePath = [[bundlesDir stringByAppendingPathComponent:SafeBasename(spec.name)] stringByAppendingPathExtension:@"tmbundle"];
			BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:bundlePath];
			bundle.installed = exists;
			bundle.path      = exists ? bundlePath : nil;

			if(exists)
			{
				NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]];
				bundle.name         = bundle.name         ?: info[@"name"];
				bundle.contactName  = bundle.contactName  ?: info[@"contactName"];
				bundle.contactEmail = bundle.contactEmail ?: to_ns(decode::rot13(to_s(info[@"contactEmailRot13"])));
				bundle.summary      = bundle.summary      ?: info[@"description"];

				NSMutableArray* grammars = [NSMutableArray array];
				for(NSDictionary* item in bundle_item_infos(info, bundlePath))
				{
					if([item[@"type"] isEqualToString:@"grammar"])
					{
						BundleGrammar* grammar = [[BundleGrammar alloc] init];
						grammar.bundle         = bundle;
						grammar.name           = item[@"name"];
						grammar.identifier     = [[NSUUID alloc] initWithUUIDString:item[@"uuid"]];
						grammar.fileType       = item[@"scope"];
						grammar.firstLineMatch = item[@"firstLineMatch"];
						grammar.filePatterns   = item[@"fileTypes"];
						[grammars addObject:grammar];
					}
				}
				bundle.grammars = [grammars copy];
			}

			res[bundle.identifier] = bundle;
		}

		// Surface any on-disk bundles not registered — e.g. user-symlinked
		// dev forks. They show in the prefs pane but have no origin and
		// cannot be auto-updated.
		for(auto const& entry : path::entries(to_s(bundlesDir), "*.tm[Bb]undle"))
		{
			NSString* bundlePath = [bundlesDir stringByAppendingPathComponent:to_ns(entry->d_name)];
			NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]];
			if(!info[@"uuid"])
				continue;
			NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:info[@"uuid"]];
			if(res[uuid])
				continue;

			Bundle* bundle = cache[uuid] ?: [[Bundle alloc] initWithIdentifier:uuid];
			bundle.installed    = YES;
			bundle.path         = bundlePath;
			bundle.name         = info[@"name"];
			bundle.contactName  = info[@"contactName"];
			bundle.contactEmail = to_ns(decode::rot13(to_s(info[@"contactEmailRot13"])));
			bundle.summary      = info[@"description"];
			bundle.category     = @"Orphaned";
			res[uuid] = bundle;
		}

		return [[res allValues] sortedArrayUsingDescriptors:@[
			[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCompare:)]
		]];
	}
}

- (NSArray<Bundle*>*)bundles
{
	if(!_bundles)
		_bundles = [self bundlesByLoadingIndex];
	return _bundles;
}

- (NSArray<Bundle*>*)bundlesByLoadingIndex
{
	NSMutableDictionary* previousBundles = [NSMutableDictionary dictionary];
	for(Bundle* bundle : _bundles)
		previousBundles[bundle.identifier] = bundle;
	return BundlesFromRegistry(_installDirectory, previousBundles);
}
@end
