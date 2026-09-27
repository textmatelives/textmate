#import <DocumentWindow/ProjectLayoutView.h>

static NSView* pane ()
{
	return [[NSView alloc] initWithFrame:NSZeroRect];
}

static ProjectLayoutView* layout_in_window ()
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 800, 600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;
	ProjectLayoutView* layout = [[ProjectLayoutView alloc] initWithFrame:NSZeroRect];
	window.contentView = layout;
	layout.documentView    = pane();
	layout.fileBrowserView = pane();
	layout.htmlOutputView  = pane();
	layout.fileBrowserWidth = 150;
	layout.htmlOutputSize   = NSMakeSize(200, 120);
	return layout;
}

// The output pane goes below, right of or left of the text view; beside it, the browser stays outermost
void test_output_pane_sits_where_placed ()
{
	ProjectLayoutView* layout = layout_in_window();
	NSRect (^doc)()    = ^{ return layout.documentView.frame; };
	NSRect (^output)() = ^{ return layout.htmlOutputView.frame; };
	NSRect (^browser)() = ^{ return layout.fileBrowserView.frame; };

	[layout layoutSubtreeIfNeeded];
	OAK_ASSERT(layout.htmlOutputPlacement == ProjectLayoutHTMLOutputBelow);
	OAK_ASSERT_LE(NSMaxY(output()), NSMinY(doc()));
	OAK_ASSERT_EQ(NSHeight(output()), 120);
	OAK_ASSERT_EQ(NSWidth(output()), 800);

	layout.htmlOutputPlacement = ProjectLayoutHTMLOutputRight;
	[layout layoutSubtreeIfNeeded];
	OAK_ASSERT_LE(NSMaxX(doc()), NSMinX(output()));
	OAK_ASSERT_EQ(NSWidth(output()), 200);
	OAK_ASSERT_EQ(NSHeight(output()), 600);
	OAK_ASSERT_LE(NSMaxX(browser()), NSMinX(doc()));

	layout.htmlOutputPlacement = ProjectLayoutHTMLOutputLeft;
	[layout layoutSubtreeIfNeeded];
	OAK_ASSERT_LE(NSMaxX(output()), NSMinX(doc()));
	OAK_ASSERT_LE(NSMaxX(browser()), NSMinX(output())); // browser, then output, then text
	OAK_ASSERT_EQ(NSWidth(output()), 200);
	OAK_ASSERT_EQ(NSHeight(output()), 600);

	layout.fileBrowserOnRight = YES;
	[layout layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(NSMinX(output()), 0);
	OAK_ASSERT_LE(NSMaxX(output()), NSMinX(doc()));
	OAK_ASSERT_LE(NSMaxX(doc()), NSMinX(browser()));

	layout.htmlOutputPlacement = ProjectLayoutHTMLOutputRight;
	[layout layoutSubtreeIfNeeded];
	OAK_ASSERT_LE(NSMaxX(doc()), NSMinX(output()));
	OAK_ASSERT_LE(NSMaxX(output()), NSMinX(browser())); // text, then output, then browser

	[layout.window close];
}
