#import <Foundation/Foundation.h>

// Command output is streamed once and its pipe is then gone. Going back or
// forward to such a page asks for its URL again, so the pages last served are
// kept here and replayed. Least recently used pages are dropped past capacity.
@interface OakHTMLOutputPageCache : NSObject
+ (instancetype)sharedCache;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)setData:(NSData*)data forKey:(NSString*)key;
- (NSData*)dataForKey:(NSString*)key;
@property (nonatomic, readonly) NSUInteger count;
@end
