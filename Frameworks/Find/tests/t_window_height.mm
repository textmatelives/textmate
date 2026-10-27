#import <Find/Find.h>
#import <OakAppKit/OakScaledContainerView.h>

// The Find window autosaves its frame, and a frame saved while the results
// pane was showing is tall. Reopened in a new process with the pane hidden
// (searching the document), the window kept that height and the options grid
// stretched to fill it. With the pane hidden the window must snap to the
// content’s height, at creation and against a user resize.

static CGFloat ContentHeight (NSWindow* window)
{
	return NSHeight([window contentRectForFrameRect:window.frame]);
}

static CGFloat CompactHeight (NSWindow* window)
{
	// The scaled container’s intrinsic size is the content’s fitting size × scale (OakScaledContainerView.h)
	return ((NSView*)window.contentView.subviews.firstObject).intrinsicContentSize.height;
}

void test_find_window_snaps_to_content_when_results_are_hidden ()
{
	NSRect screen = NSScreen.mainScreen.frame;
	NSString* tallFrame = [NSString stringWithFormat:@"%.0f %.0f 785 998 %.0f %.0f %.0f %.0f", NSMinX(screen) + 100, NSMinY(screen) + 20, NSMinX(screen), NSMinY(screen), NSWidth(screen), NSHeight(screen)];
	[NSUserDefaults.standardUserDefaults setVolatileDomain:@{ @"NSWindow Frame Find": tallFrame } forName:NSArgumentDomain];

	Find* find = Find.sharedInstance;
	find.searchTarget = FFSearchTargetDocument;
	NSWindow* window = find.window;

	OAK_ASSERT_LT(CompactHeight(window), 998);
	OAK_ASSERT_EQ(ContentHeight(window), CompactHeight(window));

	NSSize wanted = NSMakeSize(NSWidth(window.frame), NSHeight(window.frame) + 400);
	NSSize given  = [(id <NSWindowDelegate>)window.delegate windowWillResize:window toSize:wanted];
	OAK_ASSERT_EQ(given.height, NSHeight(window.frame));
	OAK_ASSERT_EQ(given.width, wanted.width);
}
