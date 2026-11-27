#import <DocumentWindow/OakCursorHistory.h>

static NSUUID* DocA ()
{
	static NSUUID* uuid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ uuid = [NSUUID UUID]; });
	return uuid;
}

static NSUUID* DocB ()
{
	static NSUUID* uuid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ uuid = [NSUUID UUID]; });
	return uuid;
}

static NSString* Sel (NSUInteger line)
{
	return [NSString stringWithFormat:@"%lu:0", line];
}

// Implicit record at a line; explicit flag records even when near.
static void Record (OakCursorHistory* h, NSUInteger line, NSUUID* doc, BOOL isExplicit)
{
	[h recordSelection:Sel(line) line:line column:0 document:doc path:@"/tmp/x" explicit:isExplicit];
}

void test_first_record_seeds ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	OAK_ASSERT_EQ(h.count, 1);
	OAK_ASSERT(h.canGoBack == NO);
	OAK_ASSERT(h.canGoForward == NO);
}

void test_explicit_jump_pushes_arrival ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 100, DocB(), YES);
	OAK_ASSERT_EQ(h.count, 2);
	OAK_ASSERT(h.canGoBack == YES);

	OakCursorHistoryEntry* back = [h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OAK_ASSERT_EQ(back.line, 10);
	OAK_ASSERT(h.canGoBack == NO);
	OAK_ASSERT(h.canGoForward == YES);

	OakCursorHistoryEntry* fwd = [h goForwardSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OAK_ASSERT_EQ(fwd.line, 100);
}

void test_nearby_move_coalesces_in_place ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 100, DocA(), NO);
	Record(h, 106, DocA(), NO); // < 12 lines: tracked, not pushed
	OAK_ASSERT_EQ(h.count, 1);
	Record(h, 200, DocA(), YES);
	OakCursorHistoryEntry* back = [h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OAK_ASSERT_EQ(back.line, 106); // returns to 106, not 100
}

void test_far_move_pushes ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 30, DocA(), NO);
	OAK_ASSERT_EQ(h.count, 2);
}

void test_explicit_records_even_when_near ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 12, DocA(), YES);
	OAK_ASSERT_EQ(h.count, 2);
}

void test_document_change_pushes ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 11, DocB(), NO); // near line, other doc: still a new entry
	OAK_ASSERT_EQ(h.count, 2);
}

void test_same_position_is_noop ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 10, DocA(), YES);
	OAK_ASSERT_EQ(h.count, 1);
}

void test_midstack_record_drops_tail ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 100, DocA(), YES);
	Record(h, 200, DocA(), YES);
	[h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	Record(h, 300, DocA(), YES);
	OAK_ASSERT_EQ(h.count, 3);
	OAK_ASSERT(h.canGoForward == NO);
	OakCursorHistoryEntry* back = [h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OAK_ASSERT_EQ(back.line, 100);
}

void test_cap_trims_oldest ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	for(NSUInteger i = 0; i < 105; ++i)
		Record(h, i * 20, DocA(), YES);
	OAK_ASSERT_EQ(h.count, 100);
	OAK_ASSERT_EQ(h.index, 99);
	OakCursorHistoryEntry* back = [h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OAK_ASSERT_EQ(back.line, (104 - 1) * 20);
}

void test_back_skips_invalid_and_prunes ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 100, DocA(), YES);
	Record(h, 200, DocA(), YES);
	OakCursorHistoryEntry* back = [h goBackSkipping:^BOOL(OakCursorHistoryEntry* e){ return e.line != 100; }];
	OAK_ASSERT_EQ(back.line, 10);
	OAK_ASSERT_EQ(h.count, 2);
	OAK_ASSERT(h.canGoBack == NO);
}

void test_forward_skips_invalid_and_prunes ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	Record(h, 100, DocA(), YES);
	Record(h, 200, DocA(), YES);
	[h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	[h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }];
	OakCursorHistoryEntry* fwd = [h goForwardSkipping:^BOOL(OakCursorHistoryEntry* e){ return e.line != 100; }];
	OAK_ASSERT_EQ(fwd.line, 200);
	OAK_ASSERT_EQ(h.count, 2);
}

void test_back_at_start_returns_nil ()
{
	OakCursorHistory* h = [OakCursorHistory new];
	Record(h, 10, DocA(), NO);
	OAK_ASSERT([h goBackSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }] == nil);
	OAK_ASSERT([h goForwardSkipping:^BOOL(OakCursorHistoryEntry*){ return YES; }] == nil);
}

void test_parse_caret_takes_last_range_max ()
{
	NSUInteger line = 0, column = 0;
	[OakCursorHistory parseCaret:@"10:4" line:&line column:&column];
	OAK_ASSERT_EQ(line, 9); // 1-based strings, 0-based internally; thresholds only need consistency
	OAK_ASSERT_EQ(column, 3);
	[OakCursorHistory parseCaret:@"3:0&50:7" line:&line column:&column];
	OAK_ASSERT_EQ(line, 49);
	OAK_ASSERT_EQ(column, 6);
	NSUInteger near = 0, far = 0, col = 0;
	[OakCursorHistory parseCaret:@"100:0" line:&near column:&col];
	[OakCursorHistory parseCaret:@"106:0" line:&far column:&col];
	OAK_ASSERT(far - near == 6); // threshold math sees true distances
}
