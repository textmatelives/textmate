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

// Called after a bundle has been replaced in place by the updater. The Dock
// and Finder learn that a bundle at a known path changed through its
// modification time, so this sets it to now and re-registers the bundle with
// Launch Services. Returns NO if the modification time could not be set.
BOOL OakNoteReplacedBundleAtURL (NSURL* bundleURL);

// YES when the version recorded at the previous launch differs from the one
// running now. A first run has no record, and the same version relaunched is
// not an update; any other change counts, downgrades included, since the
// updater offers those too.
BOOL OakVersionChangedSinceLastLaunch (NSString* lastVersion, NSString* currentVersion);

// The bundle’s icon from Icon Services, sized for NSApp.applicationIconImage.
// AppKit rasterises that image at its nominal size, and Icon Services returns
// app icons at a nominal 32×32 points, so handed over as-is the Dock and the
// ⌘Tab switcher receive a 64×64 pixel bitmap and stretch it. This raises the
// size to the largest representation. Returns nil when there is no icon.
NSImage* OakDockIconImageForBundleAtPath (NSString* path);

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
//   experimental   every tag — stable, “-beta” and “-exp” — so the user who
//                  asked for the newest of everything gets it, and converges
//                  onto the stable that absorbs their experiment (issue #142:
//                  2.5.1-undead-exp.4 users were never offered 2.6.0). An
//                  experiment is numbered as the release it targets; should
//                  that release ship without it, the experimenter falls back
//                  to stable and a continued experiment is re-cut with a
//                  higher number so it is offered again.
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

// Builds the release-notes URL for a version by the same convention —
// release.yml renders the version’s CHANGELOG.md section with bin/gen_html to
// TextMate-{version}-notes.html and uploads it next to the .tbz. Returns nil
// when either input doesn’t fit.
NSURL* OakUpdateReleaseNotesURLForVersion (NSString* version, NSURL* advertisementURL);

// Wraps a release-notes fragment (bin/gen_html output) in the document the
// update dialog renders: the given stylesheet inline, and a
// Content-Security-Policy that permits nothing beyond that stylesheet and
// data: images — no scripts, network, frames or fonts — since the fragment
// arrives over the network without the signature check the .tbz gets.
// Returns nil when the fragment is empty.
NSString* OakUpdateReleaseNotesDocument (NSString* fragment, NSString* stylesheet);

// Maps a non-2xx HTTP response to an NSError, preferring the “message” field
// GitHub puts in error bodies (e.g. “API rate limit exceeded for …”) over a
// bare status code. Returns nil for 2xx or non-HTTP responses.
NSError* OakGitHubResponseError (NSURLResponse* response, id body);
