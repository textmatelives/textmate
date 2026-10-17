#import "SoftwareUpdate.h"
#import "OakDownloadManager.h"
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakSound.h>
#import <OakAppKit/OakTransitionViewController.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScaledContainerView.h>
#import <CoreServices/CoreServices.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>

NSString* const kUserDefaultsLastSoftwareUpdateCheckKey                        = @"SoftwareUpdateLastPoll";
NSString* const kUserDefaultsSoftwareUpdateSuspendUntilKey                     = @"SoftwareUpdateSuspendUntil";
NSString* const kUserDefaultsDisableSoftwareUpdateKey                          = @"SoftwareUpdateDisablePolling";
NSString* const kUserDefaultsAskBeforeUpdatingKey                              = @"SoftwareUpdateAskBeforeUpdating";
NSString* const kUserDefaultsSoftwareUpdateChannelKey                          = @"SoftwareUpdateChannel";
NSString* const kUserDefaultsSoftwareUpdateDisableReadOnlyFileSystemWarningKey = @"SoftwareUpdateDisableReadOnlyFileSystemWarningKey";

NSString* const kSoftwareUpdateChannelRelease                                  = @"release";
NSString* const kSoftwareUpdateChannelPrerelease                               = @"beta";
NSString* const kSoftwareUpdateChannelExperimental                             = @"experimental";

// Markers release.yml stamps onto a prerelease tag. A tag carrying neither is
// a stable release.
static NSString* const kVersionMarkerBeta         = @"-beta";
static NSString* const kVersionMarkerExperimental = @"-exp";

static BOOL is_hex (char ch)
{
	return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
}

// Parses a git-upload-pack ref advertisement into a refname → SHA map.
// Returns nil when the data is not valid pkt-line format.
static NSDictionary<NSString*, NSString*>* OakRefsInUploadPackAdvertisement (NSData* data)
{
	if(!data.length)
		return nil;

	NSMutableDictionary<NSString*, NSString*>* shaForName = [NSMutableDictionary dictionary];

	char const* bytes = (char const*)data.bytes;
	NSUInteger size = data.length;
	for(NSUInteger offset = 0; offset + 4 <= size; )
	{
		NSUInteger pktLength = 0;
		for(NSUInteger i = 0; i < 4; ++i)
		{
			char ch = bytes[offset + i];
			if(!is_hex(ch))
				return nil;
			pktLength = (pktLength << 4) | (NSUInteger)(ch <= '9' ? ch - '0' : (ch | 0x20) - 'a' + 10);
		}

		if(pktLength == 0) // flush packet
		{
			offset += 4;
			continue;
		}

		if(pktLength < 4 || offset + pktLength > size)
			return nil;

		// Payload is “<40-hex-sha> <refname>[\0capabilities]\n”; the leading
		// “# service=…” pkt and anything else non-conforming is skipped.
		char const* payload = bytes + offset + 4;
		NSUInteger payloadLength = pktLength - 4;
		offset += pktLength;

		if(payloadLength < 42 || payload[40] != ' ')
			continue;

		BOOL shaValid = YES;
		for(NSUInteger i = 0; i < 40 && shaValid; ++i)
			shaValid = is_hex(payload[i]);
		if(!shaValid)
			continue;

		NSUInteger nameEnd = 41;
		while(nameEnd < payloadLength && payload[nameEnd] != '\0' && payload[nameEnd] != '\n')
			++nameEnd;
		if(nameEnd == 41)
			continue;

		NSString* sha  = [[NSString alloc] initWithBytes:payload length:40 encoding:NSASCIIStringEncoding];
		NSString* name = [[NSString alloc] initWithBytes:payload + 41 length:nameEnd - 41 encoding:NSUTF8StringEncoding];
		if(name)
			shaForName[name] = sha;
	}

	return shaForName;
}

NSString* OakSHAForRefInUploadPackAdvertisement (NSData* data, NSString* ref)
{
	if(!ref.length)
		return nil;

	NSDictionary<NSString*, NSString*>* shaForName = OakRefsInUploadPackAdvertisement(data);

	NSArray<NSString*>* candidates;
	if([ref isEqualToString:@"HEAD"])
		candidates = @[ @"HEAD" ];
	else if([ref hasPrefix:@"refs/"])
		candidates = @[ [ref stringByAppendingString:@"^{}"], ref ];
	else
		candidates = @[ [@"refs/heads/" stringByAppendingString:ref], [NSString stringWithFormat:@"refs/tags/%@^{}", ref], [@"refs/tags/" stringByAppendingString:ref] ];

	for(NSString* candidate in candidates)
	{
		if(NSString* sha = shaForName[candidate])
			return sha;
	}
	return nil;
}

// Whether `version` is one that `channel` may be offered. See the contract in
// SoftwareUpdate.h — in particular that beta converges onto stable and
// experimental deliberately does not, and that an unknown channel falls back
// to the least permissive answer rather than the most.
static BOOL OakVersionAdmissibleOnChannel (NSString* version, NSString* channel)
{
	BOOL isBeta         = [version containsString:kVersionMarkerBeta];
	BOOL isExperimental = [version containsString:kVersionMarkerExperimental];

	if([channel isEqualToString:kSoftwareUpdateChannelExperimental])
		return isExperimental;
	else if([channel isEqualToString:kSoftwareUpdateChannelPrerelease])
		return !isExperimental;
	return !isBeta && !isExperimental;
}

// How a channel is named in messages shown to the user. Matches the wording
// of the Preferences → Software Update pop-up.
static NSString* OakDisplayNameForChannel (NSString* channel)
{
	if([channel isEqualToString:kSoftwareUpdateChannelExperimental])
		return @"experimental";
	else if([channel isEqualToString:kSoftwareUpdateChannelPrerelease])
		return @"prerelease";
	return @"release";
}

NSString* OakLatestVersionInUploadPackAdvertisement (NSData* data, NSString* channel)
{
	NSString* best = nil;
	for(NSString* name in OakRefsInUploadPackAdvertisement(data))
	{
		if(![name hasPrefix:@"refs/tags/v"])
			continue;

		NSString* tag = [name substringFromIndex:[@"refs/tags/v" length]];
		if([tag hasSuffix:@"^{}"]) // peeled duplicate of an annotated tag
			tag = [tag substringToIndex:tag.length - 3];

		if(!tag.length || !isdigit([tag characterAtIndex:0])) // v2.1.0 yes, vendor-drop no
			continue;
		if(!OakVersionAdmissibleOnChannel(tag, channel))
			continue;

		if(!best || OakCompareVersionStrings(best, tag) == NSOrderedAscending)
			best = tag;
	}
	return best;
}

// {host}/{owner}/{repo}/releases/download/v{version}/{fileName}, derived from
// the advertisement URL’s /{owner}/{repo}.git/info/refs shape.
static NSURL* OakReleaseAssetURL (NSString* version, NSURL* advertisementURL, NSString* fileName)
{
	if(!version.length)
		return nil;

	// Expect /{owner}/{repo}.git/info/refs
	NSArray<NSString*>* parts = advertisementURL.path.pathComponents;
	if(parts.count != 5 || ![parts[1] length] || ![parts[2] hasSuffix:@".git"] || [parts[2] length] < 5 || ![parts[3] isEqualToString:@"info"] || ![parts[4] isEqualToString:@"refs"])
		return nil;

	NSString* repo = [parts[2] substringToIndex:[parts[2] length] - 4];
	return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/%@/%@/releases/download/v%@/%@", advertisementURL.host, parts[1], repo, version, fileName]];
}

NSURL* OakUpdateAssetURLForVersion (NSString* version, NSURL* advertisementURL)
{
	return OakReleaseAssetURL(version, advertisementURL, [NSString stringWithFormat:@"TextMate-%@.tbz", version]);
}

NSURL* OakUpdateReleaseNotesURLForVersion (NSString* version, NSURL* advertisementURL)
{
	return OakReleaseAssetURL(version, advertisementURL, [NSString stringWithFormat:@"TextMate-%@-notes.html", version]);
}

// The notes pane is styled like the About window’s Changes page, whose
// stylesheet (About/css/stylesheet.css) and background image ship in the
// application bundle. The image is inlined as a data: URI so the document
// needs no base URL and therefore no file access; the CSP permits data:
// images and nothing else. Falls back to a plain stylesheet when the About
// resources are missing, e.g. in the test runner.
static NSString* OakReleaseNotesStylesheet ()
{
	NSURL* cssURL = [NSBundle.mainBundle URLForResource:@"stylesheet" withExtension:@"css" subdirectory:@"About/css"];
	NSString* css = cssURL ? [NSString stringWithContentsOfURL:cssURL encoding:NSUTF8StringEncoding error:nullptr] : nil;
	if(!css)
		return @":root { color-scheme: light dark; }\nbody { font: 13px/1.6 -apple-system, sans-serif; color: CanvasText; margin: 1.15rem; }\na { color: LinkText; }\n";

	NSURL* imageURL = [NSBundle.mainBundle URLForResource:@"tml_image" withExtension:@"png" subdirectory:@"About/css"];
	if(NSData* image = imageURL ? [NSData dataWithContentsOfURL:imageURL] : nil)
		css = [css stringByReplacingOccurrencesOfString:@"url(\"tml_image.png\")" withString:[NSString stringWithFormat:@"url(\"data:image/png;base64,%@\")", [image base64EncodedStringWithOptions:0]]];

	// The About page sits in a 700 pt window; in a pane its margin is a bezel.
	return [css stringByAppendingString:@"\nbody { margin: 0.6rem; }\n"];
}

NSString* OakUpdateReleaseNotesDocument (NSString* fragment, NSString* stylesheet)
{
	if(![fragment stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
		return nil;

	return [NSString stringWithFormat:
		@"<!DOCTYPE html>\n"
		 "<html>\n"
		 "<head>\n"
		 "<meta charset=\"utf-8\">\n"
		 "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">\n"
		 "<style>\n%@\n</style>\n"
		 "</head>\n"
		 "<body>\n%@\n</body>\n"
		 "</html>\n", stylesheet ?: @"", fragment];
}

// Case-insensitive header lookup (HTTP/2 lowercases header names; the
// 10.15-only -valueForHTTPHeaderField: is below this framework's floor).
static NSString* OakHTTPHeaderValue (NSHTTPURLResponse* response, NSString* field)
{
	for(NSString* key in response.allHeaderFields)
	{
		if([key caseInsensitiveCompare:field] == NSOrderedSame)
		{
			NSString* value = response.allHeaderFields[key];
			return [value isKindOfClass:NSString.class] ? value : nil;
		}
	}
	return nil;
}

NSError* OakGitHubResponseError (NSURLResponse* response, id body)
{
	if(![response isKindOfClass:NSHTTPURLResponse.class])
		return nil;

	NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
	if(http.statusCode / 100 == 2)
		return nil;

	NSString* message;
	if([OakHTTPHeaderValue(http, @"x-ratelimit-remaining") isEqualToString:@"0"])
	{
		// The unauthenticated api.github.com quota (60 requests/hour per IP,
		// shared with everything else on the network) is exhausted — the
		// common cause of failed checks (issue #26). GitHub's own body
		// message is poor dialog copy, so say what happened and when the
		// quota resets.
		message = @"GitHub API rate limit reached for this network.";
		if(NSTimeInterval reset = OakHTTPHeaderValue(http, @"x-ratelimit-reset").doubleValue)
		{
			NSDateFormatter* formatter = [NSDateFormatter new];
			formatter.dateStyle = NSDateFormatterNoStyle;
			formatter.timeStyle = NSDateFormatterShortStyle;
			message = [message stringByAppendingFormat:@" Try again after %@.", [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:reset]]];
		}
	}
	else if([body isKindOfClass:NSDictionary.class] && [body[@"message"] isKindOfClass:NSString.class] && [body[@"message"] length])
	{
		message = body[@"message"]; // GitHub error bodies carry a human-readable “message”
	}
	else
	{
		message = [NSString stringWithFormat:@"HTTP %ld from update server.", (long)http.statusCode];
	}

	return [NSError errorWithDomain:@"SoftwareUpdate" code:http.statusCode userInfo:@{ NSLocalizedDescriptionKey: message }];
}

// Team Identifier of the currently running application, or nil if unsigned /
// ad-hoc signed (e.g. a local development build).
static NSString* OakRunningApplicationTeamIdentifier ()
{
	SecCodeRef selfCode = NULL;
	if(SecCodeCopySelf(kSecCSDefaultFlags, &selfCode) != errSecSuccess)
		return nil;

	NSString* teamID = nil;
	CFDictionaryRef info = NULL;
	if(SecCodeCopySigningInformation((SecStaticCodeRef)selfCode, kSecCSSigningInformation, &info) == errSecSuccess && info)
		teamID = [(__bridge NSString*)CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) copy];

	if(info)     CFRelease(info);
	if(selfCode) CFRelease(selfCode);
	return teamID;
}

// YES iff the bundle at appURL carries a valid Developer ID Application
// signature whose Team Identifier equals expectedTeamID. Fails closed when
// expectedTeamID is empty. Requirement string + flags validated by the
// 2026-05-26 Option B spike (see PLAN-eliminate-api-textmate-org.md).
static BOOL OakBundleIsSignedByTeam (NSURL* appURL, NSString* expectedTeamID)
{
	if(!expectedTeamID.length)
		return NO;

	SecStaticCodeRef code = NULL;
	if(SecStaticCodeCreateWithPath((__bridge CFURLRef)appURL, kSecCSDefaultFlags, &code) != errSecSuccess)
		return NO;

	NSString* requirement = [NSString stringWithFormat:
		@"anchor apple generic and "
		 "certificate 1[field.1.2.840.113635.100.6.2.6] exists and "      // Developer ID intermediate
		 "certificate leaf[field.1.2.840.113635.100.6.1.13] exists and "  // Developer ID Application leaf
		 "certificate leaf[subject.OU] = \"%@\"", expectedTeamID];

	SecRequirementRef req = NULL;
	OSStatus status = SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &req);
	if(status == errSecSuccess)
		status = SecStaticCodeCheckValidityWithErrors(code, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate, req, NULL);

	if(req)  CFRelease(req);
	if(code) CFRelease(code);
	return status == errSecSuccess;
}

// ============================
// = SUDownloadViewController =
// ============================

@interface SUDownloadViewController : NSViewController
- (instancetype)initWithCompletionHandler:(void(^)())completionHandler;
- (void)presentUIForBackgroundCheck:(BOOL)backgroundCheck remoteURL:(NSURL*)remoteURL remoteVersion:(NSString*)remoteVersion releaseNotes:(NSString*)releaseNotes redownloadEnabled:(BOOL)allowRedownload;
@end

// ==================
// = SoftwareUpdate =
// ==================

BOOL OakNoteReplacedBundleAtURL (NSURL* bundleURL)
{
	// The replaced bundle keeps its path, and the Dock and Finder notice a new
	// version there by its modification time (Launch Services Programming
	// Guide; Sparkle touches the installed bundle for the same reason). The
	// extracted archive carries the extraction time, which should already be
	// newer, but the time is set explicitly here so nothing depends on that,
	// and the bundle is re-registered so Launch Services is told rather than
	// left to find out.
	NSError* error;
	if(![NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:bundleURL.path error:&error])
	{
		os_log_error(OS_LOG_DEFAULT, "Unable to update the modification time of %{public}@: %{public}@", bundleURL.path, error.localizedDescription);
		return NO;
	}

	if(OSStatus rc = LSRegisterURL((__bridge CFURLRef)bundleURL, true))
		os_log_error(OS_LOG_DEFAULT, "LSRegisterURL failed for %{public}@: %d", bundleURL.path, (int)rc);

	return YES;
}

@interface SoftwareUpdate ()
{
	NSBackgroundActivityScheduler* _updateCheckScheduler;
	NSTimeInterval                 _updateCheckInterval;
}
@property (nonatomic, readwrite, getter = isChecking) BOOL checking;
@property (nonatomic, readwrite) NSString* errorString;
@property (nonatomic) BOOL automaticUpdateCheckEnabled;
@end

@implementation SoftwareUpdate
+ (instancetype)sharedInstance
{
	static SoftwareUpdate* sharedInstance = [self new];
	return sharedInstance;
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		kUserDefaultsSoftwareUpdateChannelKey: kSoftwareUpdateChannelRelease
	}];
}

- (instancetype)init
{
	if(self = [super init])
	{
		_updateCheckInterval = 60*60;

		[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults queue:nil usingBlock:^(NSNotification* notification){
			dispatch_async(dispatch_get_main_queue(), ^{
				self.automaticUpdateCheckEnabled = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSoftwareUpdateKey];
			});
		}];
		self.automaticUpdateCheckEnabled = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSoftwareUpdateKey];
	}
	return self;
}

- (void)setAutomaticUpdateCheckEnabled:(BOOL)flag
{
	if(_automaticUpdateCheckEnabled == flag)
		return;

	[_updateCheckScheduler invalidate];
	_updateCheckScheduler = nil;

	if(_automaticUpdateCheckEnabled = flag)
	{
		_updateCheckScheduler = [[NSBackgroundActivityScheduler alloc] initWithIdentifier:[NSString stringWithFormat:@"%@.%@", NSBundle.mainBundle.bundleIdentifier, @"SoftwareUpdate"]];
		_updateCheckScheduler.interval = _updateCheckInterval;
		_updateCheckScheduler.repeats  = YES;
		[_updateCheckScheduler scheduleWithBlock:^(NSBackgroundActivityCompletionHandler completionHandler){
			if(NSDate* suspendUntil = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsSoftwareUpdateSuspendUntilKey])
			{
				if([suspendUntil timeIntervalSinceNow] > 0)
				{
					os_log(OS_LOG_DEFAULT, "Skip version check: Suspended until %{public}@", suspendUntil);
					completionHandler(NSBackgroundActivityResultFinished);
					return;
				}
				[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsSoftwareUpdateSuspendUntilKey];
			}

			[self checkWithCompletionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSString* releaseNotes, NSError* error){
				self.errorString = error ? [NSString stringWithFormat:@"Error: %@", error.localizedDescription] : nil;
				if(error)
				{
					os_log(OS_LOG_DEFAULT, "Failed to check for update: %{public}@", error.localizedDescription);
					completionHandler(NSBackgroundActivityResultFinished);
				}
				else
				{
					SUDownloadViewController* alertViewController = [[SUDownloadViewController alloc] initWithCompletionHandler:^{
						completionHandler(NSBackgroundActivityResultFinished);
					}];
					[alertViewController presentUIForBackgroundCheck:YES remoteURL:remoteURL remoteVersion:remoteVersion releaseNotes:releaseNotes redownloadEnabled:NO];
				}
			}];
		}];
	}
}

- (void)checkForUpdate:(id)sender
{
	BOOL isShiftDown = OakIsAlternateKeyOrMouseEvent(NSEventModifierFlagShift);

	[self checkWithCompletionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSString* releaseNotes, NSError* error){
		SUDownloadViewController* alertViewController = [[SUDownloadViewController alloc] init];
		if(error)
				[alertViewController presentError:error];
		else	[alertViewController presentUIForBackgroundCheck:NO remoteURL:remoteURL remoteVersion:remoteVersion releaseNotes:releaseNotes redownloadEnabled:isShiftDown];
	}];
}

- (void)checkWithCompletionHandler:(void(^)(NSURL* remoteURL, NSString* remoteVersion, NSString* releaseNotes, NSError* error))completionHandler
{
	// The channel is whatever Preferences → Software Update is set to; there
	// is no modifier-key override, so what a user is offered always matches
	// what the pop-up says.
	NSString* updateChannel = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsSoftwareUpdateChannelKey];
	if(!updateChannel)
		return completionHandler(nil, nil, nil, [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"No channel configured." }]);

	NSURL* url = _channels[updateChannel];
	if(!url)
		return completionHandler(nil, nil, nil, [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No channel named ‘%@’.", updateChannel] }]);

	os_activity_initiate("Software update check", OS_ACTIVITY_FLAG_DEFAULT, ^{
		self.checking = YES;

		NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60];
		[request setValue:OakDownloadManager.sharedInstance.userAgentString forHTTPHeaderField:@"User-Agent"];

		NSURLSessionDataTask* dataTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error){
			NSURL* remoteURL;
			NSString* remoteVersion;

			if(!error)
			{
				NSString* contentType = ((NSHTTPURLResponse*)response).allHeaderFields[@"Content-Type"];

				// Error bodies (e.g. from a proxy or a metered endpoint) are
				// JSON; the feed itself is a ref advertisement.
				id body = nil;
				if([contentType hasPrefix:@"application/json"])
					body = [NSJSONSerialization JSONObjectWithData:data options:0 error:nullptr];

				if(NSError* httpError = OakGitHubResponseError(response, body))
				{
					error = httpError;
				}
				else if([contentType hasPrefix:@"application/x-git-upload-pack-advertisement"])
				{
					remoteVersion = OakLatestVersionInUploadPackAdvertisement(data, updateChannel);
					remoteURL     = OakUpdateAssetURLForVersion(remoteVersion, url);
					if(!remoteURL || !remoteVersion)
					{
						// Tell an empty channel apart from an unreadable feed. A
						// channel with nothing published is an ordinary state —
						// experimental streams exist only while an experiment is
						// running — so saying the server sent no tags would be
						// both wrong and alarming. The probe re-reads the same
						// response against the release channel: if that finds a
						// version, the feed was fine and the channel is simply
						// empty. (The stringWithFormat: is parenthesised because
						// its comma would otherwise read as an argument separator
						// to the enclosing os_activity_initiate macro — brackets
						// do not group for the preprocessor, parentheses do.)
						NSString* message = OakLatestVersionInUploadPackAdvertisement(data, kSoftwareUpdateChannelRelease)
							? ([NSString stringWithFormat:@"No %@ builds have been published yet.", OakDisplayNameForChannel(updateChannel)])
							: @"No release tags in server response.";
						error = [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: message }];
					}
				}
				else
				{
					// 200 with the wrong content type — e.g. a captive portal’s
					// HTML — names itself instead of “Incomplete server response.”
					// (Message built outside the dictionary literal: a comma there
					// breaks the enclosing os_activity_initiate macro expansion.)
					NSString* message = [@"Unexpected response type from update server: " stringByAppendingString:contentType ?: @"none"];
					error = [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: message }];
				}
			}

			// Only an offered update shows the dialog the notes go in, so only
			// then are they fetched. (Commas stay inside parentheses: this is
			// still the body of the os_activity_initiate macro.)
			NSString* localVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
			NSURL* notesURL = (!error && OakCompareVersionStrings(localVersion, remoteVersion) == NSOrderedAscending) ? OakUpdateReleaseNotesURLForVersion(remoteVersion, url) : nil;

			[self fetchReleaseNotesAtURL:notesURL completionHandler:^(NSString* releaseNotes){
				dispatch_async(dispatch_get_main_queue(), ^{
					[NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:kUserDefaultsLastSoftwareUpdateCheckKey];
					self.checking = NO;
					completionHandler(remoteURL, remoteVersion, releaseNotes, error);
				});
			}];
		}];
		[dataTask resume];
	});
}

// Fetches the rendered release notes for an offered version. The notes are an
// optional pane on the update dialog, so every failure — no asset on this
// release (none published before this shipped carries one), a slow network,
// a body that is not text — completes with nil and the dialog appears without
// the pane, as it did before. The dialog waits for this before it is shown,
// so that it appears complete rather than growing a pane after the fact; the
// short timeout keeps a manual check responsive when the asset is slow.
- (void)fetchReleaseNotesAtURL:(NSURL*)url completionHandler:(void(^)(NSString* fragment))completionHandler
{
	if(!url)
		return completionHandler(nil);

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
	[request setValue:OakDownloadManager.sharedInstance.userAgentString forHTTPHeaderField:@"User-Agent"];

	NSURLSessionDataTask* dataTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error){
		NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
		NSString* fragment = (!error && statusCode == 200) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
		if(!fragment)
			os_log(OS_LOG_DEFAULT, "No release notes at %{public}@: %{public}@", url.absoluteString, error ? error.localizedDescription : [NSString stringWithFormat:@"HTTP %ld", (long)statusCode]);
		completionHandler(fragment);
	}];
	[dataTask resume];
}
@end

// ============================
// = SUDownloadViewController =
// ============================

@interface SUInfoViewController : NSViewController
@property (nonatomic) NSTextField* messageTextField;
@property (nonatomic) NSTextField* informativeTextField;
// Set when the dialog is wider than the text column would make it — a
// release-notes pane below — so the column takes the width it is given
// instead of its own 298 pt. Optional priorities do not work here: any pull
// toward a narrower width makes AppKit snap a resized window back to it.
@property (nonatomic) BOOL fillsWidth;
@end

@interface SUProgressViewController : NSViewController
@property (nonatomic) NSTextField*         messageTextField;
@property (nonatomic) NSTextField*         informativeTextField;
@property (nonatomic) NSProgressIndicator* progressIndicator;
@property (nonatomic) NSProgress*          progress;
@end

@interface SUDownloadViewController () <WKNavigationDelegate>
{
	SUDownloadViewController* _retainedSelf;

	NSBox*     _releaseNotesBox;
	WKWebView* _releaseNotesView;

	void(^_completionHandler)();
	BOOL(^_runModalCompletionHandler)(NSModalResponse);

	NSURL* _downloadedArchiveURL;
	NSURL* _remoteURL;

	NSStackView* _buttonStackView;
}
@property (nonatomic, getter = isUpdateBadgeVisible) BOOL updateBadgeVisible;
@property (nonatomic) NSImage* dockImageBeforeUpdateBadge;

@property (nonatomic) OakTransitionViewController*  contentViewController;
@property (nonatomic) SUInfoViewController*         infoViewController;
@property (nonatomic) SUProgressViewController*     progressViewController;
@property (nonatomic, readonly) NSArray<NSButton*>* buttons;
- (NSButton*)addButtonWithTitle:(NSString*)title;
@end

@implementation SUDownloadViewController
- (instancetype)initWithCompletionHandler:(void(^)())completionHandler
{
	if(self = [super initWithNibName:nil bundle:nil])
	{
		_completionHandler      = completionHandler;

		_contentViewController  = [[OakTransitionViewController alloc] init];
		_infoViewController     = [[SUInfoViewController alloc] init];
		_progressViewController = [[SUProgressViewController alloc] init];

		self.title = @"";
	}
	return self;
}

- (instancetype)init
{
	return [self initWithCompletionHandler:nil];
}

- (void)dealloc
{
	_releaseNotesView.navigationDelegate = nil;
	[_releaseNotesView stopLoading];

	if(_completionHandler)
		_completionHandler();
}

- (NSStackView*)buttonStackView
{
	if(!_buttonStackView)
	{
		_buttonStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
		_buttonStackView.spacing = 16;
		[_buttonStackView setHuggingPriority:NSLayoutPriorityDefaultHigh-1 forOrientation:NSLayoutConstraintOrientationVertical];
	}
	return _buttonStackView;
}

- (NSArray<NSButton*>*)buttons
{
	return self.buttonStackView.views.reverseObjectEnumerator.allObjects;
}

- (NSButton*)addButtonWithTitle:(NSString*)title
{
	NSUInteger countOfButtons = self.buttons.count;

	NSButton* button = [NSButton buttonWithTitle:title target:self action:@selector(didClickButton:)];
	button.tag = NSAlertFirstButtonReturn + countOfButtons;
	if(countOfButtons == 0)
		button.keyEquivalent = @"\r";
	else if([title isEqualToString:@"Cancel"])
		button.keyEquivalent = @"\e";

	[button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	NSLayoutConstraint* widthConstraint = [button.widthAnchor constraintEqualToConstant:86];
	widthConstraint.priority = NSLayoutPriorityDefaultHigh;
	widthConstraint.active = YES;

	[self.buttonStackView insertView:button atIndex:0 inGravity:NSStackViewGravityTrailing];

	return button;
}

- (void)loadView
{
	NSImage* image = [NSImage imageNamed:NSImageNameApplicationIcon];
	image.size = NSMakeSize(64, 64);

	NSMutableDictionary* views = [@{
		@"image":   [NSImageView imageViewWithImage:image],
		@"content": self.contentViewController.view,
		@"buttons": self.buttonStackView,
	} mutableCopy];
	if(_releaseNotesBox)
		views[@"notes"] = _releaseNotesBox;

	NSView* contentView = [[NSView alloc] initWithFrame:NSZeroRect];
	OakAddAutoLayoutViewsToSuperview(views.allValues, contentView);

	[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(24)-[image(==64)]-(16)-[content]-|" options:NSLayoutFormatAlignAllTop metrics:nil views:views]];
	[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[image]-(>=20)-[buttons]-|"            options:0                         metrics:nil views:views]];
	[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(16)-[image(==64)]-(>=20)-|"         options:0                         metrics:nil views:views]];

	if(_releaseNotesBox)
	{
		// The pane runs the full width under the icon and the text column,
		// hugging whichever of the two ends lower, and takes all the height the
		// window has to give (its vertical hugging priority is the lowest in
		// the dialog).
		[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(24)-[notes]-|"                           options:0 metrics:nil views:views]];
		[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[image]-(==12@750,>=12)-[notes]"             options:0 metrics:nil views:views]];
		[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[content]-(>=12)-[notes]-(20)-[buttons]-(18)-|" options:0 metrics:nil views:views]];
	}
	else
	{
		[NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[content]-(==20@750,>=20@250)-[buttons]-(18)-|" options:0 metrics:nil views:views]];
	}

	self.view = contentView;
}

// Adds a pane with the offered version’s release notes, laid out by
// -loadView, so this must run before the view loads. Scripts are off, and the
// document’s Content-Security-Policy admits no subresources beyond data:
// images (OakUpdateReleaseNotesDocument), so the pane renders text, links and
// the About page’s backdrop, and nothing else. The size is a minimum: the
// panel becomes resizable once the pane exists (-runModalWithCompletionHandler:).
- (void)showReleaseNotesDocument:(NSString*)html
{
	NSAssert(!self.viewLoaded, @"release notes must be added before the view loads");

	if(!_releaseNotesBox)
	{
		self.infoViewController.fillsWidth = YES;

		WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
		configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;

		_releaseNotesView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
		_releaseNotesView.navigationDelegate = self;

		_releaseNotesBox = [[NSBox alloc] initWithFrame:NSZeroRect];
		_releaseNotesBox.boxType            = NSBoxCustom;
		_releaseNotesBox.borderColor        = NSColor.separatorColor;
		_releaseNotesBox.cornerRadius       = 5;
		_releaseNotesBox.contentViewMargins = NSZeroSize;
		_releaseNotesBox.contentView        = _releaseNotesView;
		[_releaseNotesBox setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
		[_releaseNotesBox.widthAnchor  constraintGreaterThanOrEqualToConstant:560].active = YES;
		[_releaseNotesBox.heightAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;
	}
	[_releaseNotesView loadHTMLString:html baseURL:nil];
}

// The only navigation the pane starts itself is the loadHTMLString: above,
// which loads as about:blank. Anything else is a link in the notes: it goes
// to the browser, and the pane stays on the notes.
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	if(navigationAction.navigationType == WKNavigationTypeOther && [navigationAction.request.URL.absoluteString isEqualToString:@"about:blank"])
		return decisionHandler(WKNavigationActionPolicyAllow);

	if(navigationAction.request.URL)
		[NSWorkspace.sharedWorkspace openURL:navigationAction.request.URL];
	decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)viewWillAppear
{
	_retainedSelf = self;
}

- (void)viewDidDisappear
{
	self.updateBadgeVisible = NO;
	[_progressViewController.progress cancel];

	if(_downloadedArchiveURL)
	{
		NSError* error;
		if(![NSFileManager.defaultManager removeItemAtURL:_downloadedArchiveURL error:&error])
			os_log_error(OS_LOG_DEFAULT, "Unable to remove %{public}@: %{public}@", _downloadedArchiveURL.path, error.localizedDescription);
		_downloadedArchiveURL = nil;
	}

	_retainedSelf = nil;
}

- (BOOL)presentError:(NSError*)error
{
	self.contentViewController.subview = self.infoViewController.view;

	self.infoViewController.messageTextField.stringValue     = @"Error Checking for Update";
	self.infoViewController.informativeTextField.stringValue = error.localizedDescription;
	[self addButtonWithTitle:@"OK"];

	[self runModalWithCompletionHandler:nil];

	return YES;
}

- (void)presentAlertWithMessage:(NSString*)messageText informativeText:(NSString*)informativeText buttonTitles:(NSArray<NSString*>*)buttonTitles completionHandler:(BOOL(^)(NSModalResponse))completionHandler
{
	NSAlert* alert = [[NSAlert alloc] init];

	alert.messageText     = messageText;
	alert.informativeText = informativeText;

	for(NSString* title in buttonTitles)
		[alert addButtonWithTitle:title];

	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode){
		if(!completionHandler || completionHandler(returnCode))
			[self.view.window close];
	}];
}

- (void)runModalWithCompletionHandler:(BOOL(^)(NSModalResponse))completionHandler
{
	// Not windowWithContentViewController: the view goes into an
	// OakScaledContainerView so the dialog zooms with the UI scale. The view
	// controller still gets its appearance callbacks from its view’s window.
	NSWindow* window = [[NSPanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;
	OakSetScaledWindowContentView(window, self.view);

	window.animationBehavior       = NSWindowAnimationBehaviorAlertPanel;
	window.excludedFromWindowsMenu = YES;
	window.hidesOnDeactivate       = NO;
	window.level                   = NSModalPanelWindowLevel;
	window.styleMask               = NSWindowStyleMaskTitled;

	// With release notes on board the panel may be resized to read them; the
	// pane takes the extra space (SUInfoViewController) and the fitting size
	// is the floor.
	if(_releaseNotesBox)
	{
		window.styleMask      |= NSWindowStyleMaskResizable;
		window.contentMinSize  = window.contentView.fittingSize; // the zoomed view

		// A resizable titled window grows the three title-bar buttons, two of
		// them disabled; this is still an alert, so keep the title bar bare.
		for(NSWindowButton button : { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton })
			[window standardWindowButton:button].hidden = YES;
	}

	// If we use -[NSApplication runModalForWindow:] then the window
	// won’t stay above document windows after the modal session ends
	_runModalCompletionHandler = completionHandler;
	[window makeKeyAndOrderFront:self];
}

- (void)didClickButton:(id)sender
{
	if(!_runModalCompletionHandler || _runModalCompletionHandler([sender tag]))
		[self.view.window close];
	_runModalCompletionHandler = nil;
}

- (void)setUpdateBadgeVisible:(BOOL)flag
{
	if(_updateBadgeVisible == flag)
		return;

	if(_updateBadgeVisible = flag)
	{
		if(NSImage* dlBadge = [NSImage imageNamed:@"Update Badge" inSameBundleAsClass:[self class]])
		{
			NSImage* appIcon = NSApp.applicationIconImage;
			self.dockImageBeforeUpdateBadge = appIcon;
			NSApp.applicationIconImage = [NSImage imageWithSize:appIcon.size flipped:NO drawingHandler:^BOOL(NSRect dstRect){
				NSRect upperRightRect = NSIntersectionRect(dstRect, NSOffsetRect(dstRect, round(NSWidth(dstRect) * 2 / 3), (NSHeight(dstRect) * 2 / 3)));
				[appIcon drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
				[dlBadge drawInRect:upperRightRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
				return YES;
			}];
		}
	}
	else
	{
		// Restore what was there, which may be the image set on the first launch
		// of a new version (AboutWindowController), not merely the bundle icon.
		NSApp.applicationIconImage = self.dockImageBeforeUpdateBadge;
		self.dockImageBeforeUpdateBadge = nil;
	}
}

- (void)presentUIForBackgroundCheck:(BOOL)backgroundCheck remoteURL:(NSURL*)remoteURL remoteVersion:(NSString*)remoteVersion releaseNotes:(NSString*)releaseNotes redownloadEnabled:(BOOL)allowRedownload
{
	NSString* localVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSComparisonResult ordering = OakCompareVersionStrings(localVersion, remoteVersion);

	if(backgroundCheck && ordering != NSOrderedAscending)
		return;

	self.contentViewController.subview = self.infoViewController.view;

	if(ordering == NSOrderedAscending)
	{
		self.infoViewController.messageTextField.stringValue     = @"New Version Available";
		self.infoViewController.informativeTextField.stringValue = [NSString stringWithFormat: @"%@ %@ is now available. You have version %@. Would you like to download it now?", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"], remoteVersion, localVersion];

		if(NSString* document = OakUpdateReleaseNotesDocument(releaseNotes, OakReleaseNotesStylesheet()))
			[self showReleaseNotesDocument:document];

		[self addButtonWithTitle:@"Download"];
		[self addButtonWithTitle:backgroundCheck ? @"Later" : @"Cancel"];
		self.buttons.lastObject.keyEquivalent = @"\e";
	}
	else if(ordering == NSOrderedSame)
	{
		self.infoViewController.messageTextField.stringValue     = @"Up To Date";
		self.infoViewController.informativeTextField.stringValue = [NSString stringWithFormat:@"You are running %@ which is the latest version available.", remoteVersion];

		[self addButtonWithTitle:@"OK"];
		if(allowRedownload)
			[self addButtonWithTitle:@"Redownload"];
	}
	else if(ordering == NSOrderedDescending)
	{
		self.infoViewController.messageTextField.stringValue     = @"You are Using a Prerelease";
		self.infoViewController.informativeTextField.stringValue = [NSString stringWithFormat:@"%@ is the latest version available. You have version %@.", remoteVersion, localVersion];

		[self addButtonWithTitle:@"OK"];
		[self addButtonWithTitle:[NSString stringWithFormat:@"Downgrade to %@", remoteVersion]];
	}

	[self runModalWithCompletionHandler:^BOOL(NSModalResponse response){
		if(response == (ordering == NSOrderedAscending ? NSAlertFirstButtonReturn : NSAlertSecondButtonReturn))
		{
			struct statfs sfsb;
			if(statfs(NSBundle.mainBundle.bundlePath.fileSystemRepresentation, &sfsb) == 0 && (sfsb.f_flags & MNT_RDONLY))
			{
				NSString* informativeText = [NSString stringWithFormat:@"%1$@ is running on a read-only file system and can therefore not be updated.\n\nIf you downloaded %1$@ from the internet then moving it out of the Downloads folder should solve the problem.", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
				[self presentAlertWithMessage:@"Read-only File System" informativeText:informativeText buttonTitles:@[ @"OK" ] completionHandler:^BOOL(NSModalResponse returnCode){
					return YES; // Close window
				}];
			}
			else
			{
				[self downloadSoftwareUpdateAtURL:remoteURL];
			}
			return NO; // Keep window open
		}
		else
		{
			if(backgroundCheck)
				[NSUserDefaults.standardUserDefaults setObject:[[NSDate date] dateByAddingTimeInterval:24*60*60] forKey:kUserDefaultsSoftwareUpdateSuspendUntilKey];
			return YES; // Close window
		}
	}];
}

- (void)cancel:(id)sender
{
	[self.view.window close];
}

- (void)takeURLToDownloadFrom:(NSButton*)sender
{
	[self downloadSoftwareUpdateAtURL:sender.cell.representedObject];
}

- (void)downloadSoftwareUpdateAtURL:(NSURL*)downloadURL
{
	_remoteURL = downloadURL;

	id <NSProgressReporting> progressReporting = [OakDownloadManager.sharedInstance downloadArchiveAtURL:downloadURL forReplacingURL:NSBundle.mainBundle.bundleURL completionHandler:^(NSURL* extractedArchiveURL, NSError* error){
		self.progressViewController.progress = nil;

		if(extractedArchiveURL)
		{
			self.updateBadgeVisible = YES;
			if(NSApp.isActive)
				OakPlayUISound(OakSoundDidCompleteSomethingUISound);

			self.progressViewController.messageTextField.stringValue = [NSString stringWithFormat:@"Downloaded %@", downloadURL.lastPathComponent];

			self.buttons[0].enabled                = YES;
			self.buttons[0].cell.representedObject = extractedArchiveURL;
			self.buttons[0].action                 = @selector(takeURLToInstallFrom:);

			_downloadedArchiveURL = extractedArchiveURL; // Will be deleted in viewDidDisappear
		}
		else
		{
			self.progressViewController.messageTextField.stringValue     = @"Error Downloading Update";
			self.progressViewController.informativeTextField.stringValue = error.localizedDescription ?: @"";

			self.buttons[0].title                  = @"Retry";
			self.buttons[0].enabled                = YES;
			self.buttons[0].cell.representedObject = downloadURL;
			self.buttons[0].action                 = @selector(takeURLToDownloadFrom:);
		}
	}];

	self.progressViewController.progress = progressReporting.progress;
	self.contentViewController.subview = self.progressViewController.view;

	self.buttons[0].title         = @"Install & Relaunch";
	self.buttons[0].enabled       = NO;

	self.buttons[1].title         = @"Cancel";
	self.buttons[1].action        = @selector(cancel:);
	self.buttons[1].keyEquivalent = @"\e";
}

- (BOOL)isInstallableApplicationAtURL:(NSURL*)applicationURL
{
	NSError* error;
	NSNumber* boolean;
	BOOL res = [[applicationURL URLByAppendingPathComponent:[NSString stringWithFormat:@"Contents/MacOS/%@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]] isDirectory:NO] getResourceValue:&boolean forKey:NSURLIsExecutableKey error:&error] && boolean.boolValue;
	if(!res && error)
		os_log_error(OS_LOG_DEFAULT, "Failed checking if %{public}@ has an executable: %{public}@", applicationURL.path, error.localizedDescription);
	return res;
}

- (void)takeURLToInstallFrom:(NSButton*)sender
{
	NSURL* applicationURL = sender.cell.representedObject;

	if([self isInstallableApplicationAtURL:applicationURL])
	{
		// Trust gate: the update must carry a valid Developer ID Application
		// signature whose Team Identifier matches the running app. Distinct from
		// the integrity (incomplete-download) failure below — a trust failure is
		// not fixed by redownloading, so we do not offer that here.
		NSString* expectedTeamID = OakRunningApplicationTeamIdentifier();
		if(!OakBundleIsSignedByTeam(applicationURL, expectedTeamID))
		{
			os_log_error(OS_LOG_DEFAULT, "Software update rejected: %{public}@ is not signed by the expected Developer ID team (%{public}@)", applicationURL.path, expectedTeamID ?: @"<none>");
			[self presentAlertWithMessage:@"Update Could Not Be Verified" informativeText:@"The downloaded update is not signed by the expected developer, so it will not be installed.\n\nDownload the latest version manually from the project’s Releases page." buttonTitles:@[ @"OK" ] completionHandler:^BOOL(NSModalResponse returnCode){
				return YES; // close the update window
			}];
			return;
		}

		self.progressViewController.messageTextField.stringValue     = [NSString stringWithFormat:@"Installing %@…", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
		self.progressViewController.informativeTextField.stringValue = @"";
		self.progressViewController.progressIndicator.indeterminate  = YES;
		[self.progressViewController.progressIndicator startAnimation:self];

		self.buttons[0].enabled = NO;
		self.buttons[1].enabled = NO;

		NSError* error;
		if([NSFileManager.defaultManager replaceItemAtURL:NSBundle.mainBundle.bundleURL withItemAtURL:applicationURL backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:nil error:&error])
		{
			OakNoteReplacedBundleAtURL(NSBundle.mainBundle.bundleURL);

			self.progressViewController.messageTextField.stringValue = [NSString stringWithFormat:@"Relaunching %@…", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];

			NSString* script = [NSString stringWithFormat:@"{ kill %1$d; while ps -xp %1$d; do if (( ++n == 300 )); then exit; fi; sleep .2; done; open \"$0\" --args $1; } &>/dev/null &", getpid()];

			NSTask* task = [[NSTask alloc] init];
			task.launchPath     = @"/bin/sh";
			task.arguments      = @[ @"-c", script, NSBundle.mainBundle.bundlePath, @"-showReleaseNotes YES" ];
			task.standardInput  = NSFileHandle.fileHandleWithNullDevice;
			task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
			task.standardError  = NSFileHandle.fileHandleWithNullDevice;

			@try {
				[task launch];
			}
			@catch (NSException* e) {
				os_log_error(OS_LOG_DEFAULT, "-[NSTask launch]: %{public}@", e.reason);
			}
		}
		else
		{
			[self.progressViewController.progressIndicator stopAnimation:self];
			self.progressViewController.progressIndicator.indeterminate = NO;

			[self presentAlertWithMessage:@"Failed to Install Update" informativeText:error.localizedDescription buttonTitles:@[ @"Retry", @"Cancel" ] completionHandler:^BOOL(NSModalResponse returnCode){
				if(returnCode == NSAlertFirstButtonReturn)
					[self takeURLToInstallFrom:sender];
				return returnCode == NSAlertSecondButtonReturn; // Close window if clicking “Cancel”
			}];
		}
	}
	else
	{
		[self presentAlertWithMessage:@"Integrity Check Failed" informativeText:@"The download is incomplete. This can happen if the system has been deleting temporary files.\n\nWould you like to redownload the update?" buttonTitles:@[ @"Redownload", @"Cancel" ] completionHandler:^BOOL(NSModalResponse returnCode){
			if(returnCode == NSAlertFirstButtonReturn)
			{
				[self downloadSoftwareUpdateAtURL:_remoteURL];

				NSError* error;
				if(![NSFileManager.defaultManager removeItemAtURL:applicationURL error:&error])
					os_log_error(OS_LOG_DEFAULT, "Unable to remove %{public}@: %{public}@", applicationURL.path, error.localizedDescription);

				_downloadedArchiveURL = nil;
			}
			return returnCode == NSAlertSecondButtonReturn; // Close window if clicking “Cancel”
		}];
	}
}
@end

// ========================
// = SUInfoViewController =
// ========================

@interface SUInfoViewController ()
{
	NSLayoutConstraint* _widthConstraint;
}
@end

@implementation SUInfoViewController
- (void)setFillsWidth:(BOOL)flag
{
	_fillsWidth = flag;
	_widthConstraint.active = !flag;
}

- (void)loadView
{
	_messageTextField     = [NSTextField labelWithString:@"New Version Available"];
	_informativeTextField = [NSTextField wrappingLabelWithString:@"Would you like to download and install?"];

	NSStackView* stackView = [NSStackView stackViewWithViews:@[
		_messageTextField, _informativeTextField
	]];

	stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
	stackView.alignment   = NSLayoutAttributeLeading;
	[stackView setHuggingPriority:NSLayoutPriorityDefaultHigh-1 forOrientation:NSLayoutConstraintOrientationVertical];

	_messageTextField.selectable     = YES;
	_messageTextField.font           = [NSFont boldSystemFontOfSize:0];
	_informativeTextField.selectable = YES;
	_informativeTextField.font       = [NSFont messageFontOfSize:NSFont.smallSystemFontSize];

	_widthConstraint = [stackView.widthAnchor constraintEqualToConstant:298];
	_widthConstraint.active = !_fillsWidth;

	self.view = stackView;
}
@end

// ============================
// = SUProgressViewController =
// ============================

@interface SUProgressViewController ()
{
	NSTimer* _checkProgressTimer;
}
@end

@implementation SUProgressViewController
- (void)loadView
{
	_messageTextField     = [NSTextField labelWithString:@"Downloading Archive…"];
	_progressIndicator    = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	_informativeTextField = [NSTextField labelWithString:@"999.9 MB of 999.9 MB — About 59 minutes, 59 seconds remaining"];

	_messageTextField.selectable     = YES;
	_progressIndicator.maxValue      = 1;
	_progressIndicator.indeterminate = NO;
	_informativeTextField.font       = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
	_informativeTextField.selectable = YES;

	NSStackView* stackView = [NSStackView stackViewWithViews:@[
		_messageTextField, _progressIndicator, _informativeTextField
	]];
	stackView.spacing     = 0;
	stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
	stackView.alignment   = NSLayoutAttributeLeading;

	[stackView.widthAnchor constraintGreaterThanOrEqualToConstant:_informativeTextField.fittingSize.width + 20].active = YES;

	self.view = stackView;
}

- (void)viewWillAppear
{
	if(_progress)
		[self checkProgressTimerDidFire:nil];
}

- (void)viewDidDisappear
{
	[_checkProgressTimer invalidate];
}

- (void)setProgress:(NSProgress*)newProgress
{
	if(_progress && !newProgress)
		[self checkProgressTimerDidFire:nil];

	if(_progress = newProgress)
	{
		[self checkProgressTimerDidFire:nil];

		_checkProgressTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(checkProgressTimerDidFire:) userInfo:nil repeats:YES];
		[self checkProgressTimerDidFire:_checkProgressTimer];
	}
	else
	{
		[_checkProgressTimer invalidate];
		_checkProgressTimer = nil;
	}
}

- (void)checkProgressTimerDidFire:(NSTimer*)timer
{
	_messageTextField.stringValue     = _progress.localizedDescription;
	_informativeTextField.stringValue = _progress.isIndeterminate ? @"Estimating time remaining." : _progress.localizedAdditionalDescription;
	_progressIndicator.doubleValue    = _progress.fractionCompleted;
}
@end
