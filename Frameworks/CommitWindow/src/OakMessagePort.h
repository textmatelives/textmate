#import <Foundation/Foundation.h>

// Process-to-process messaging over CFMessagePort, carrying property lists.
// Replaces the Distributed Objects link between the commit tool and the app.
// Compiled into the framework and into the tool (which links only
// Foundation), so it must not depend on anything else.

typedef NSDictionary* (^OakMessagePortHandler)(NSDictionary* request);

// Registers `name` in the bootstrap namespace and answers requests on the
// run loop of the thread that created it.
@interface OakMessagePortServer : NSObject
@property (nonatomic, readonly) NSString* name;
// nil when the name is already taken.
- (instancetype)initWithName:(NSString*)name handler:(OakMessagePortHandler)handler;
- (void)invalidate;
@end

// Sends `request` to the server registered as `name` and returns its reply,
// an empty dictionary when the server returned no data, or nil when no
// server answered within `timeout` seconds.
NSDictionary* OakMessagePortSendRequest (NSString* name, NSDictionary* request, NSTimeInterval timeout);
