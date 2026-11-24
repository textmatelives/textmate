#import <OakTextView/OakTextView.h>
#import <selection/types.h>

// OakAccessibleLink is private to OakTextView.mm; this is the slice of its
// interface the tests need. Lives in a header because gen_test wraps test
// bodies in a namespace and Objective-C declarations must be global.
@interface OakAccessibleLink : NSObject
- (id)initWithTextView:(OakTextView*)textView range:(ng::range_t)range title:(NSString*)title URL:(NSString*)URL frame:(NSRect)frame;
@end
