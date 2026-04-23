#import "BundleRegistry.h"
#import "BundleSpec.h"
#import "MandatoryBundles.h"
#import <oak/debug.h>
#import <sys/xattr.h>
#import <sys/stat.h>

static NSString* const kStateFileName   = @"Bundles.plist";
static NSString* const kKeyBundles      = @"bundles";
static NSString* const kKeySchemaVersion = @"schemaVersion";
static NSInteger const kCurrentSchemaVersion = 1;

@interface BundleRegistry ()
{
	NSMutableDictionary<NSUUID*, BundleSpec*>* _specs;
}
@property (nonatomic, readwrite) NSString* stateFilePath;
@end

@implementation BundleRegistry

+ (instancetype)sharedInstance
{
	static BundleRegistry* sharedInstance = [self new];
	return sharedInstance;
}

- (instancetype)init
{
	if(self = [super init])
	{
		NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
		_stateFilePath = [[appSupport stringByAppendingPathComponent:@"TextMate"] stringByAppendingPathComponent:kStateFileName];
		_specs = [NSMutableDictionary dictionary];
		[self reload];
	}
	return self;
}

- (void)reload
{
	[_specs removeAllObjects];

	NSDictionary* root = [NSDictionary dictionaryWithContentsOfFile:_stateFilePath];
	if(root)
	{
		for(NSDictionary* entry in root[kKeyBundles])
		{
			if(BundleSpec* spec = [[BundleSpec alloc] initWithPlistRepresentation:entry])
				_specs[spec.uuid] = spec;
		}
	}

	[self seedMandatory];
	[self seedShippedDefaults];

	// migrateExistingInstalls runs once, only when Bundles.plist is absent.
	if(!root)
		[self migrateExistingInstalls];

	// Persist whenever we mutate (new specs seeded, categories refreshed,
	// or migration ran). Cheap — writing a small plist is fine on every
	// launch.
	[self save];
}

// Phase-6 migration: if Bundles.plist does not yet exist but there are
// bundles already sitting in ~/Library/Application Support/TextMate/
// Managed/Bundles/ (from a legacy install), record them as already-installed
// so the first poll doesn't wipe the user's existing directories. Only
// specs that were just seeded from shipped defaults are affected; orphans
// stay orphans.
- (void)migrateExistingInstalls
{
	NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
	NSString* bundlesDir = [[appSupport stringByAppendingPathComponent:@"TextMate/Managed"] stringByAppendingPathComponent:@"Bundles"];
	NSFileManager* fm = NSFileManager.defaultManager;

	for(BundleSpec* spec in _specs.allValues)
	{
		if(spec.origin == TMBundleOriginMandatory) // handled separately
			continue;
		if(spec.installedSHA)
			continue;

		NSString* candidate = [[bundlesDir stringByAppendingPathComponent:spec.name] stringByAppendingPathExtension:@"tmbundle"];
		if(![fm fileExistsAtPath:candidate])
			continue;

		// Read the legacy xattr (oak::date_t strings or a SHA we set ourselves).
		const char* cPath = candidate.fileSystemRepresentation;
		char value[128] = { 0 };
		ssize_t n = getxattr(cPath, "org.textmate.bundle.updated", value, sizeof(value) - 1, 0, 0);
		NSString* legacyValue = (n > 0) ? [[NSString alloc] initWithBytes:value length:(NSUInteger)n encoding:NSUTF8StringEncoding] : nil;

		spec.installedSHA = legacyValue.length ? legacyValue : @"legacy-install";
		spec.installedAt  = [NSDate date];
		os_log(OS_LOG_DEFAULT, "Migrated existing bundle %{public}@ (legacy marker %{public}@)", spec.name, legacyValue ?: @"(none)");
	}
}

- (void)seedMandatory
{
	for(size_t i = 0; i < kTMMandatoryBundleCount; ++i)
	{
		TMMandatoryBundle const& m = kTMMandatoryBundles[i];
		NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:m.uuid]];
		if(!uuid)
			continue;

		NSString* sha = [NSString stringWithUTF8String:m.sha];
		NSString* category = m.category ? [NSString stringWithUTF8String:m.category] : @"Other";
		BundleSpec* existing = _specs[uuid];
		if(!existing)
		{
			existing = [[BundleSpec alloc] initWithUUID:uuid
			                                       name:[NSString stringWithUTF8String:m.name]
			                                        url:[NSString stringWithUTF8String:m.url]
			                                        ref:sha];
			_specs[uuid] = existing;
		}
		else
		{
			// The user may not rewrite url/ref for a mandatory bundle; we
			// silently restore the pinned values on every load.
			existing.ref = sha;
		}
		existing.category = category;
		existing.origin = TMBundleOriginMandatory;
	}
}

- (void)seedShippedDefaults
{
	NSString* path = [NSBundle.mainBundle pathForResource:@"DefaultBundles" ofType:@"plist"];
	if(!path)
		return;

	NSDictionary* root = [NSDictionary dictionaryWithContentsOfFile:path];
	for(NSDictionary* entry in root[kKeyBundles])
	{
		NSString* uuidStr = entry[@"uuid"];
		NSUUID* uuid = uuidStr ? [[NSUUID alloc] initWithUUIDString:uuidStr] : nil;
		if(!uuid)
			continue;

		BundleSpec* existing = _specs[uuid];
		if(existing)
		{
			// Don't overwrite user-edited url/ref/autoUpdate, but refresh
			// shipped metadata (category, and name when the user hasn't
			// customized it) every launch so the scope bar stays current
			// as DefaultBundles.plist evolves.
			if(existing.origin != TMBundleOriginMandatory)
			{
				if(NSString* c = entry[@"category"])
					existing.category = c;
			}
			continue;
		}

		BundleSpec* spec = [[BundleSpec alloc] initWithPlistRepresentation:entry];
		if(!spec)
			continue;
		spec.origin = TMBundleOriginShipped;
		_specs[spec.uuid] = spec;
	}
}

- (NSArray<BundleSpec*>*)allSpecs
{
	return [_specs.allValues sortedArrayUsingDescriptors:@[
		[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCompare:)]
	]];
}

- (BundleSpec*)specForUUID:(NSUUID*)uuid
{
	return _specs[uuid];
}

- (BOOL)addSpec:(BundleSpec*)spec
{
	if(!spec || _specs[spec.uuid])
		return NO;
	_specs[spec.uuid] = spec;
	return [self save];
}

- (BOOL)updateSpec:(BundleSpec*)spec
{
	BundleSpec* existing = _specs[spec.uuid];
	if(!existing)
		return NO;

	if(existing.origin == TMBundleOriginMandatory)
	{
		if(![existing.url isEqualToString:spec.url] || ![existing.ref isEqualToString:spec.ref])
		{
			os_log_error(OS_LOG_DEFAULT, "Refusing to mutate mandatory bundle %{public}@: url/ref are pinned", existing.name);
			return NO;
		}
	}

	_specs[spec.uuid] = spec;
	return [self save];
}

- (BOOL)removeSpecForUUID:(NSUUID*)uuid
{
	BundleSpec* existing = _specs[uuid];
	if(!existing)
		return NO;
	if(existing.origin == TMBundleOriginMandatory)
	{
		os_log_error(OS_LOG_DEFAULT, "Refusing to remove mandatory bundle %{public}@", existing.name);
		return NO;
	}
	[_specs removeObjectForKey:uuid];
	return [self save];
}

- (NSString*)managedBundlesPath
{
	NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
	return [[appSupport stringByAppendingPathComponent:@"TextMate/Managed"] stringByAppendingPathComponent:@"Bundles"];
}

- (void)ensureMandatoryBundlesOnDisk
{
	NSString* bundlesDir = [self managedBundlesPath];
	NSString* embeddedDir = [NSBundle.mainBundle.sharedSupportPath stringByAppendingPathComponent:@"Bundles"];

	NSFileManager* fm = NSFileManager.defaultManager;
	NSError* err;
	if(![fm fileExistsAtPath:bundlesDir] && ![fm createDirectoryAtPath:bundlesDir withIntermediateDirectories:YES attributes:nil error:&err])
	{
		os_log_error(OS_LOG_DEFAULT, "Failed to create %{public}@: %{public}@", bundlesDir, err.localizedDescription);
		return;
	}

	BOOL mutated = NO;
	for(size_t i = 0; i < kTMMandatoryBundleCount; ++i)
	{
		TMMandatoryBundle const& m = kTMMandatoryBundles[i];
		NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:m.uuid]];
		BundleSpec* spec = _specs[uuid];
		if(!spec)
			continue;

		NSString* bundleName = [NSString stringWithFormat:@"%@.tmbundle", spec.name];
		NSString* destPath   = [bundlesDir stringByAppendingPathComponent:bundleName];
		NSString* srcPath    = [embeddedDir stringByAppendingPathComponent:bundleName];

		// Respect developer symlinks (reset_bundles.sh). Never overwrite a
		// symlinked mandatory bundle — record a sentinel SHA and move on.
		// User's dev workflow wins over embedded copy. lstat needed here —
		// attributesOfItemAtPath: silently follows symlinks.
		struct stat st;
		if(lstat(destPath.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode))
		{
			if(!spec.installedSHA)
			{
				spec.installedSHA = @"symlink";
				spec.installedAt  = [NSDate date];
				mutated = YES;
			}
			os_log(OS_LOG_DEFAULT, "Skipping symlinked mandatory bundle %{public}@", spec.name);
			continue;
		}

		BOOL alreadyAtPinnedSHA = [spec.installedSHA isEqualToString:spec.ref] && [fm fileExistsAtPath:destPath];
		if(alreadyAtPinnedSHA)
			continue;

		if(![fm fileExistsAtPath:srcPath])
		{
			os_log_error(OS_LOG_DEFAULT, "Mandatory bundle missing from .app: %{public}@", srcPath);
			continue;
		}

		if([fm fileExistsAtPath:destPath] && ![fm removeItemAtPath:destPath error:&err])
		{
			os_log_error(OS_LOG_DEFAULT, "Failed to remove stale %{public}@: %{public}@", destPath, err.localizedDescription);
			continue;
		}

		if(![fm copyItemAtPath:srcPath toPath:destPath error:&err])
		{
			os_log_error(OS_LOG_DEFAULT, "Failed to copy %{public}@ → %{public}@: %{public}@", srcPath, destPath, err.localizedDescription);
			continue;
		}

		spec.installedSHA = spec.ref;
		spec.installedAt  = [NSDate date];
		mutated = YES;
		os_log(OS_LOG_DEFAULT, "Installed mandatory bundle %{public}@ @ %{public}@ from embedded", spec.name, spec.installedSHA);
	}

	if(mutated)
		[self save];
}

- (BOOL)save
{
	NSFileManager* fm = NSFileManager.defaultManager;
	NSString* dir = [_stateFilePath stringByDeletingLastPathComponent];
	NSError* err;
	if(![fm fileExistsAtPath:dir] && ![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err])
	{
		os_log_error(OS_LOG_DEFAULT, "Failed to create %{public}@: %{public}@", dir, err.localizedDescription);
		return NO;
	}

	NSMutableArray* entries = [NSMutableArray array];
	for(BundleSpec* spec in self.allSpecs)
		[entries addObject:spec.plistRepresentation];

	NSDictionary* root = @{
		kKeySchemaVersion: @(kCurrentSchemaVersion),
		kKeyBundles:       entries,
	};

	if(![root writeToFile:_stateFilePath atomically:YES])
	{
		os_log_error(OS_LOG_DEFAULT, "Failed to write %{public}@", _stateFilePath);
		return NO;
	}
	return YES;
}

@end
