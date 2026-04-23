#import <Foundation/Foundation.h>

@class BundleSpec;

// Fetches bundle archives from GitHub via codeload.github.com, extracts
// them into a target directory, and resolves branch/tag refs to current
// SHAs via the REST API.
//
// Transport is plain HTTPS with no cryptographic verification beyond TLS.
// Trust is rooted in GitHub's certificate chain plus the user's decision
// to subscribe to a given url/ref pair.

// Result of a SHA resolution.
@interface BundleSHAResolution : NSObject
@property (nonatomic, readonly) NSString* sha;   // 40-char hex
@property (nonatomic, readonly) NSString* etag;  // opaque, pass back on next call
@property (nonatomic, readonly) BOOL      notModified; // YES when server returned 304
@end

@interface BundleFetcher : NSObject

+ (instancetype)sharedInstance;

// Parse https://github.com/owner/repo[.tmbundle] into owner/repo. Returns
// NO on malformed URLs. Exposed for tests and the fetcher's internal use.
+ (BOOL)parseURL:(NSString*)url owner:(NSString**)owner repo:(NSString**)repo;

// GET /repos/{owner}/{repo}/commits/{ref} with optional If-None-Match.
// Completion fires on the main queue.
- (void)resolveSHAForSpec:(BundleSpec*)spec
          conditionalEtag:(NSString*)etag
               completion:(void(^)(BundleSHAResolution* resolution, NSError* error))completion;

// Download codeload tarball for spec.url @ spec.ref, stream through tar,
// validate the resulting directory contains a matching info.plist, and
// atomically swap it into destURL. Fills spec.installedSHA / installedAt
// on success. Completion fires on the main queue.
- (void)fetchAndInstallSpec:(BundleSpec*)spec
                  intoURL:(NSURL*)destURL
                completion:(void(^)(NSString* installedSHA, NSError* error))completion;

@end
