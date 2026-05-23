#import <Foundation/Foundation.h>

@class BundleSpec;

// Persistent state store for bundle subscriptions. Backed by a single plist
// at ~/Library/Application Support/TextMate/Bundles.plist.
//
// Phase 1: read/write only. No fetching, no UI wiring. BundlesManager does
// not yet consult this; kept side-by-side with the legacy index path.
//
// On first read, if the state file does not exist, the registry seeds
// itself from kTMMandatoryBundles and the shipped DefaultBundles.plist.
// Mandatory entries are re-seeded on every load if missing.

@interface BundleRegistry : NSObject

+ (instancetype)sharedInstance;

// Path to the on-disk state file. Exposed for the pref pane "Edit state
// file…" affordance and for tests.
@property (nonatomic, readonly) NSString* stateFilePath;

// Immutable snapshot of current specs, sorted by name.
@property (nonatomic, readonly) NSArray<BundleSpec*>* allSpecs;

- (BundleSpec*)specForUUID:(NSUUID*)uuid;

// Add a new spec. Rejects and returns NO if a spec with the same UUID
// already exists. Persists on success.
- (BOOL)addSpec:(BundleSpec*)spec;

// Replace an existing spec. Rejects and returns NO if the spec's UUID is
// not registered, or if the caller attempts to mutate a mandatory entry's
// url/ref. Persists on success.
- (BOOL)updateSpec:(BundleSpec*)spec;

// Remove a spec by UUID. Rejects and returns NO for mandatory UUIDs.
// Persists on success.
- (BOOL)removeSpecForUUID:(NSUUID*)uuid;

// For each mandatory spec, ensure Managed/Bundles/<name>.tmbundle/ exists
// on disk and carries the pinned SHA. Missing or stale directories are
// restored by copying from the .app's embedded SharedSupport/Bundles/.
// Runs synchronously; no network.
- (void)ensureMandatoryBundlesOnDisk;

// Force a save. Normally unnecessary — mutators persist automatically.
- (BOOL)save;

// Reload from disk, discarding any in-memory state. Useful after the user
// edits Bundles.plist externally.
- (void)reload;

// Look up an uninstalled catalogue spec by lowercase file extension via the
// build-time BundleFileTypeIndex.plist. Returns nil when (a) ext is nil or
// empty, (b) the extension is not in the index, (c) the matching bundle is
// already installed (installedSHA non-nil), (d) the index references a UUID
// missing from the spec table, or (e) the index plist itself is absent.
- (BundleSpec*)bundleSpecForFileExtension:(NSString*)ext;

// Parses the BundleFileTypeIndex.plist at `path` into an extension → UUID
// dictionary. Returns an empty dictionary (never nil) when the file is
// missing or unparseable. Entries with malformed UUIDs are silently
// dropped. Lowercases keys defensively even though the generator emits
// lowercase already.
+ (NSDictionary<NSString*, NSUUID*>*)loadFileTypeIndexFromPath:(NSString*)path;

// Resolve a catalogue resource (DefaultBundles.plist, AvailableBundles.plist,
// BundleFileTypeIndex.plist) to an on-disk path. The files live in
// Bundle Support.tmbundle/Support/; preference goes to the managed install
// under ~/Library/Application Support/TextMate/Managed/Bundles/, falling
// back to the embedded copy under <App>/Contents/SharedSupport/Bundles/
// for first launch and offline. Returns nil if neither exists.
+ (NSString*)pathForCatalogueResource:(NSString*)basename;

// Test seam: construct a registry against an explicit spec list and index
// path, bypassing the singleton's seeding pipeline. Not for production
// callers.
- (instancetype)initForTestingWithSpecs:(NSArray<BundleSpec*>*)specs
                      fileTypeIndexPath:(NSString*)indexPath;

@end
