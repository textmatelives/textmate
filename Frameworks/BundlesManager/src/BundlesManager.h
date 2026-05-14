#import "Bundle.h"
#import <bundles/item.h>

@class BundleSpec;

extern NSString* const kUserDefaultsDisableBundleUpdatesKey;
extern NSString* const kUserDefaultsLastBundleUpdateCheckKey;

// Per-bundle dismissal list for the on-demand bundle prompt (Phase 2).
// Array of NSString UUIDs. Distinct from kUserDefaultsGrammarsToNeverSuggestKey
// (declared file-static in DocumentWindowController.mm), which stores grammar
// UUIDs for the legacy installed-bundle suggestion flow.
extern NSString* const kUserDefaultsBundlesToNeverSuggestKey;

@interface BundlesManager : NSObject
@property (class, readonly) BundlesManager* sharedInstance;

@property (nonatomic, readonly) NSArray<Bundle*>* bundles;

- (NSProgress*)installBundles:(NSArray<Bundle*>*)someBundles completionHandler:(void(^)(NSArray<Bundle*>*))callback;

// Install one or more uninstalled catalogue bundles by spec. Mirrors
// installBundles: but accepts BundleSpec* directly — for callers that have
// a spec (e.g. via bundleSpecForFileExtension:) but no realized Bundle*.
// Fetches via BundleFetcher, persists install state through BundleRegistry,
// then reloads the bundle index. Completion fires on the main queue with
// the newly-installed specs.
- (NSProgress*)installSpecs:(NSArray<BundleSpec*>*)someSpecs completionHandler:(void(^)(NSArray<BundleSpec*>*))callback;
- (void)uninstallBundle:(Bundle*)aBundle;
// Fully remove a bundle's registry entry in addition to uninstalling it.
// The bundle disappears from the list until re-added by URL.
- (void)removeBundleSpec:(Bundle*)aBundle;
- (void)loadBundlesIndex;
- (void)installBundleItemsAtPaths:(NSArray*)somePaths;
- (BOOL)findBundleForInstall:(bundles::item_ptr*)res;
- (void)reloadPath:(NSString*)aPath;

// Phase-3 hook. Copies any missing mandatory bundles from the .app's
// Contents/SharedSupport/Bundles/ into ~/Library/Application Support/
// TextMate/Managed/Bundles/. Synchronous, no network.
- (void)ensureMandatoryBundlesOnDisk;

// Subscribe to a new bundle by git URL. Resolves current SHA and fetches
// immediately. `ref` defaults to "main" when nil/empty. `name` is optional
// — if nil the bundle name is derived from the fetched info.plist.
// Completion fires on the main queue with the resolved SHA (nil on error).
- (void)addBundleFromURL:(NSString*)url
                     ref:(NSString*)ref
                    name:(NSString*)name
              completion:(void(^)(NSString* installedSHA, NSError* error))completion;

// Force one immediate poll cycle across all registry specs. Useful for
// "Check for Updates Now" UI.
- (void)checkForBundleUpdatesNowWithCompletion:(void(^)(void))completion;

// Toggle per-bundle auto-update. Persists immediately.
- (void)setAutoUpdate:(BOOL)autoUpdate forBundle:(Bundle*)bundle;

// Update the registered spec's url and/or ref, then re-fetch. Pass nil to
// leave a field unchanged. On success fires completion with the resolved
// SHA; on failure with an NSError.
- (void)updateBundle:(Bundle*)bundle
                 url:(NSString*)newURL
                 ref:(NSString*)newRef
          completion:(void(^)(NSString* installedSHA, NSError* error))completion;

// Revert a shipped-default spec back to its DefaultBundles.plist url/ref
// and re-fetch. No-op for mandatory or user-added specs.
- (void)revertBundleToDefault:(Bundle*)bundle
                   completion:(void(^)(NSString* installedSHA, NSError* error))completion;

// Returns YES if bundle's registered spec differs from DefaultBundles.plist
// (user edited a shipped default). Returns NO for mandatory/user-added.
- (BOOL)bundleIsEditedShippedDefault:(Bundle*)bundle;

// Look up an uninstalled catalogue spec by lowercase file extension via the
// build-time BundleFileTypeIndex.plist. Returns nil when no catalogue match
// exists or when the matching bundle is already installed. Used by the
// on-demand bundle prompt (Phase 2).
- (BundleSpec*)bundleSpecForFileExtension:(NSString*)ext;
@end
