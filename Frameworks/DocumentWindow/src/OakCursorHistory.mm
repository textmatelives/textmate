#import "OakCursorHistory.h"
#import <text/types.h>

static NSUInteger const kMaxEntries = 100;
static NSUInteger const kCoalesceThresholdLines = 12;

@implementation OakCursorHistory (Parsing)

+ (void)parseCaret:(NSString*)sel line:(NSUInteger*)line column:(NSUInteger*)column
{
	text::selection_t selection(std::string(sel ? sel.UTF8String : ""));
	text::pos_t caret = selection.last().max();
	*line = caret.line;
	*column = caret.column;
}

@end

@implementation OakCursorHistoryEntry
- (instancetype)initWithDocument:(NSUUID*)docID path:(NSString*)path selection:(NSString*)sel line:(NSUInteger)line column:(NSUInteger)col
{
	if(self = [super init])
	{
		_documentIdentifier = docID;
		_path = [path copy];
		_selectionString = [sel copy];
		_line = line;
		_column = col;
	}
	return self;
}
@end

@interface OakCursorHistory ()
@property (nonatomic) NSMutableArray<OakCursorHistoryEntry*>* entries;
@property (nonatomic) NSUInteger index;
@end

@implementation OakCursorHistory

- (instancetype)init
{
	if(self = [super init])
		_entries = [NSMutableArray new];
	return self;
}

- (NSUInteger)count
{
	return _entries.count;
}

- (BOOL)samePosition:(OakCursorHistoryEntry*)a as:(OakCursorHistoryEntry*)b
{
	return [a.documentIdentifier isEqual:b.documentIdentifier] && [a.selectionString isEqualToString:b.selectionString];
}

- (void)recordSelection:(NSString*)sel line:(NSUInteger)line column:(NSUInteger)col document:(NSUUID*)docID path:(NSString*)path explicit:(BOOL)isExplicitJump
{
	OakCursorHistoryEntry* state = [[OakCursorHistoryEntry alloc] initWithDocument:docID path:path selection:sel line:line column:col];
	if(_entries.count == 0)
	{
		[_entries addObject:state];
		_index = 0;
		return;
	}

	// Nearby moves update the top entry in place, so by the time a real
	// jump is pushed, the top already holds the immediate departure point;
	// no separate drift-stashing is needed.
	OakCursorHistoryEntry* top = _entries[_index];
	if([self samePosition:state as:top])
		return;

	NSUInteger lineDistance = line > top.line ? line - top.line : top.line - line;
	BOOL sameDocument = [docID isEqual:top.documentIdentifier];
	if(isExplicitJump || !sameDocument || lineDistance >= kCoalesceThresholdLines)
	{
		NSRange tail = NSMakeRange(_index + 1, _entries.count - _index - 1);
		if(tail.length > 0)
			[_entries removeObjectsInRange:tail];
		[_entries addObject:state];
		_index = _entries.count - 1;
		if(_entries.count > kMaxEntries)
		{
			[_entries removeObjectAtIndex:0];
			_index -= 1;
		}
	}
	else // nearby move in the same document: track the caret in place
	{
		_entries[_index] = state;
	}
}

- (OakCursorHistoryEntry*)goBackSkipping:(BOOL(^)(OakCursorHistoryEntry*))isValid
{
	while(_index > 0)
	{
		if(isValid(_entries[_index - 1]))
		{
			_index -= 1;
			return _entries[_index];
		}
		[_entries removeObjectAtIndex:_index - 1];
		_index -= 1;
	}
	return nil;
}

- (OakCursorHistoryEntry*)goForwardSkipping:(BOOL(^)(OakCursorHistoryEntry*))isValid
{
	while(_index + 1 < _entries.count)
	{
		if(isValid(_entries[_index + 1]))
		{
			_index += 1;
			return _entries[_index];
		}
		[_entries removeObjectAtIndex:_index + 1];
	}
	return nil;
}

- (BOOL)canGoBack
{
	return _index > 0;
}

- (BOOL)canGoForward
{
	return _index + 1 < _entries.count;
}

@end
