#import <Foundation/Foundation.h>

// Browser-style cursor history: a linear stack of (document, position)
// entries with an index. New records mid-stack drop the forward tail.
// Same-document moves within kCoalesceThreshold lines update the top
// entry in place; explicit jumps always push.

@interface OakCursorHistoryEntry : NSObject
@property (nonatomic, readonly) NSUUID* documentIdentifier;
@property (nonatomic, readonly) NSString* path; // nil for untitled documents
@property (nonatomic, readonly) NSString* selectionString;
@property (nonatomic, readonly) NSUInteger line;
@property (nonatomic, readonly) NSUInteger column;
- (instancetype)initWithDocument:(NSUUID*)docID path:(NSString*)path selection:(NSString*)sel line:(NSUInteger)line column:(NSUInteger)col;
@end

@interface OakCursorHistory : NSObject
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger index;
+ (void)parseCaret:(NSString*)sel line:(NSUInteger*)line column:(NSUInteger*)column;
- (void)recordSelection:(NSString*)sel line:(NSUInteger)line column:(NSUInteger)col document:(NSUUID*)docID path:(NSString*)path explicit:(BOOL)isExplicitJump;
- (OakCursorHistoryEntry*)goBackSkipping:(BOOL(^)(OakCursorHistoryEntry*))isValid;
- (OakCursorHistoryEntry*)goForwardSkipping:(BOOL(^)(OakCursorHistoryEntry*))isValid;
- (BOOL)canGoBack;
- (BOOL)canGoForward;
@end
