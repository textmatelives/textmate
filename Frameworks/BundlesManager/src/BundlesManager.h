#import "Bundle.h"
#import <bundles/item.h>

extern NSString* const kUserDefaultsDisableBundleUpdatesKey;
extern NSString* const kUserDefaultsLastBundleUpdateCheckKey;

@interface BundlesManager : NSObject
@property (class, readonly) BundlesManager* sharedInstance;

@property (nonatomic, readonly) NSArray<Bundle*>* bundles;

- (NSProgress*)installBundles:(NSArray<Bundle*>*)someBundles completionHandler:(void(^)(NSArray<Bundle*>*))callback;
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
@end
