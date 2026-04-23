#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TMBundleOrigin) {
	TMBundleOriginUser      = 0,
	TMBundleOriginShipped   = 1,
	TMBundleOriginMandatory = 2,
};

// Value object: everything needed to fetch, track, and describe one bundle
// subscription. Serializable to/from a plist dictionary so it can be
// persisted in ~/Library/Application Support/TextMate/Bundles.plist.
//
// Immutable for identifying fields (uuid, url); mutable for state that
// changes at poll/install time (installedSHA, installedAt, etag,
// autoUpdate, ref).
@interface BundleSpec : NSObject <NSCopying>

- (instancetype)initWithUUID:(NSUUID*)uuid
                         name:(NSString*)name
                          url:(NSString*)url
                          ref:(NSString*)ref;

// Returns nil if the dict is missing required keys (uuid, name, url).
- (instancetype)initWithPlistRepresentation:(NSDictionary*)plist;

- (NSDictionary*)plistRepresentation;

@property (nonatomic, readonly) NSUUID*   uuid;
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* url;

// Mutable state
@property (nonatomic)           NSString* ref;             // branch/tag/SHA; default "main"
@property (nonatomic)           BOOL      autoUpdate;      // default YES
@property (nonatomic)           TMBundleOrigin origin;     // set at load, not persisted

// Install state (nil until first successful install)
@property (nonatomic)           NSString* installedSHA;
@property (nonatomic)           NSDate*   installedAt;
@property (nonatomic)           NSString* etag;

// YES if ref is a 40-char hex SHA — skip polling for these.
@property (nonatomic, readonly) BOOL isPinnedToSHA;

@end
