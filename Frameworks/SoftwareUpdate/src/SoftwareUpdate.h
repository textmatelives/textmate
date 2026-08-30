extern NSString* const kUserDefaultsDisableSoftwareUpdateKey;
extern NSString* const kUserDefaultsSoftwareUpdateChannelKey;
extern NSString* const kUserDefaultsAskBeforeUpdatingKey;
extern NSString* const kUserDefaultsLastSoftwareUpdateCheckKey;

extern NSString* const kSoftwareUpdateChannelRelease;
extern NSString* const kSoftwareUpdateChannelPrerelease;
extern NSString* const kSoftwareUpdateChannelExperimental;

@interface SoftwareUpdate : NSObject
@property (class, readonly) SoftwareUpdate* sharedInstance;

@property (nonatomic) NSDictionary<NSString*, NSURL*>* channels;
@property (nonatomic, readonly, getter = isChecking) BOOL checking;
@property (nonatomic, readonly) NSString* errorString;

- (void)checkForUpdate:(id)sender;
@end

NSComparisonResult OakCompareVersionStrings (NSString* lhsString, NSString* rhsString);

// The update feed is git’s smart-HTTP ref advertisement (the body of
// GET {repo}.git/info/refs?service=git-upload-pack — what `git ls-remote`
// uses). Unlike api.github.com it is unmetered, so update checks cannot be
// starved by the 60-requests/hour-per-IP API quota (issue #26).

// Extracts the commit SHA for `ref` from a ref advertisement. A bare name
// tries refs/heads/<ref> first, then refs/tags/<ref> — preferring the peeled
// (^{}) commit of an annotated tag over the tag object. Returns nil when the
// ref is absent or the data is not a valid advertisement.
NSString* OakSHAForRefInUploadPackAdvertisement (NSData* data, NSString* ref);

// Returns the highest version (per OakCompareVersionStrings) among the
// advertisement’s refs/tags/v<digit>… tags that `channel` is allowed to see,
// stripped of the leading “v”. Returns nil if no tag qualifies or the data is
// malformed.
//
// Channels are distinguished by the markers release.yml stamps onto a tag:
//
//   release        stable tags only (no marker).
//   beta           stable + “-beta”, so a beta user converges back onto
//                  stable once it catches up — beta content ships as stable
//                  eventually.
//   experimental   “-exp” only, deliberately WITHOUT that convergence: an
//                  experimental stream may never merge, so offering a newer
//                  stable would silently take away the feature the user opted
//                  in to test.
//
// An unrecognised (or nil) channel is treated as release — the least
// permissive reading, so a stale or hand-edited default cannot widen what a
// user is offered.
NSString* OakLatestVersionInUploadPackAdvertisement (NSData* data, NSString* channel);

// Builds the release-asset URL for a version by convention — release.yml
// uploads TextMate-{version}.tbz onto release v{version} — from the
// advertisement URL’s {host}/{owner}/{repo}.git/info/refs shape. Returns nil
// when either input doesn’t fit.
NSURL* OakUpdateAssetURLForVersion (NSString* version, NSURL* advertisementURL);

// Maps a non-2xx HTTP response to an NSError, preferring the “message” field
// GitHub puts in error bodies (e.g. “API rate limit exceeded for …”) over a
// bare status code. Returns nil for 2xx or non-HTTP responses.
NSError* OakGitHubResponseError (NSURLResponse* response, id body);
