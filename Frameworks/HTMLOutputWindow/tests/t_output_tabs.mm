#import <HTMLOutputWindow/HTMLOutputWindow.h>
#import <HTMLOutputWindow/OakHTMLOutputTabView.h>
#import "OutputTabsDelegate.h" // the test runner puts test bodies in a namespace, where an Objective-C class cannot be declared

static OakHTMLOutputView* add_view (OakHTMLOutputTabView* tabView)
{
	OakHTMLOutputView* view = [[OakHTMLOutputView alloc] initWithFrame:NSZeroRect];
	[tabView addHTMLOutputView:view];
	return view;
}

static NSUInteger shown_count (OakHTMLOutputTabView* tabView)
{
	NSUInteger res = 0;
	for(OakHTMLOutputView* view in tabView.htmlOutputViews)
		res += view.isHidden ? 0 : 1;
	return res;
}

void test_adding_a_view_selects_it_and_hides_the_others ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* first  = add_view(tabView);
	OakHTMLOutputView* second = add_view(tabView);

	OAK_ASSERT_EQ(tabView.htmlOutputViews.count, 2);
	OAK_ASSERT(tabView.selectedHTMLOutputView == second);
	OAK_ASSERT(first.isHidden);
	OAK_ASSERT(!second.isHidden);
	OAK_ASSERT_EQ(shown_count(tabView), 1);
	OAK_ASSERT_EQ(tabView.tabBarView.selectedTabIndex, 1);
	OAK_ASSERT(first.superview != nil && second.superview != nil); // every view stays in the hierarchy, so its window stays known

	[tabView revealHTMLOutputView:first];
	OAK_ASSERT(tabView.selectedHTMLOutputView == first);
	OAK_ASSERT(!first.isHidden);
	OAK_ASSERT(second.isHidden);
	OAK_ASSERT_EQ(tabView.tabBarView.selectedTabIndex, 0);
}

void test_a_view_reveals_its_tab_through_the_responder_chain ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* first = add_view(tabView);
	add_view(tabView);

	OAK_ASSERT([first tryToPerform:@selector(revealHTMLOutputView:) with:first]);
	OAK_ASSERT(tabView.selectedHTMLOutputView == first);
}

void test_removing_the_selected_view_selects_a_neighbour ()
{
	OutputTabsDelegate* delegate = [OutputTabsDelegate new];
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	tabView.delegate = delegate;
	OakHTMLOutputView* first  = add_view(tabView);
	OakHTMLOutputView* second = add_view(tabView);
	OakHTMLOutputView* third  = add_view(tabView);

	[tabView setSelectedHTMLOutputView:second];
	[tabView removeHTMLOutputView:second];
	OAK_ASSERT_EQ(tabView.htmlOutputViews.count, 2);
	OAK_ASSERT(tabView.selectedHTMLOutputView == third); // the tab that took its place
	OAK_ASSERT(second.superview == nil);

	[tabView removeHTMLOutputView:third];
	OAK_ASSERT(tabView.selectedHTMLOutputView == first);
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 0);

	[tabView removeHTMLOutputView:first];
	OAK_ASSERT(tabView.selectedHTMLOutputView == nil);
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 1);
}

void test_the_tab_bar_can_live_outside_the_view ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OAK_ASSERT(tabView.tabBarView.superview == tabView);
	tabView.hostsTabBar = NO;
	OAK_ASSERT(tabView.tabBarView.superview == nil);
	tabView.hostsTabBar = YES;
	OAK_ASSERT(tabView.tabBarView.superview == tabView);
}

// The window shows one tab per output view and its title follows the selected one
void test_the_output_window_hosts_tabs ()
{
	[NSApplication sharedApplication];
	HTMLOutputWindowController* controller = [[HTMLOutputWindowController alloc] initWithIdentifier:[NSUUID UUID]];
	OakHTMLOutputView* first = controller.htmlOutputView;
	OAK_ASSERT(first != nil);
	OAK_ASSERT_EQ(controller.tabView.htmlOutputViews.count, 1);
	OAK_ASSERT(controller.tabView.tabBarView.superview != controller.tabView); // the tab bar sits in the title bar

	OakHTMLOutputView* second = [controller newHTMLOutputView];
	OAK_ASSERT_EQ(controller.tabView.htmlOutputViews.count, 2);
	OAK_ASSERT(controller.htmlOutputView == second);

	[controller.tabView removeHTMLOutputView:second];
	OAK_ASSERT(controller.htmlOutputView == first);
	[controller close];
}

void test_views_are_found_by_the_command_they_show ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	NSUUID* command = [NSUUID UUID];
	OakHTMLOutputView* view = add_view(tabView);
	view.commandIdentifier = command;
	add_view(tabView);

	OAK_ASSERT([tabView htmlOutputViewForIdentifier:command busy:NO] == view);
	OAK_ASSERT([tabView htmlOutputViewForIdentifier:command busy:YES] == nil);
	OAK_ASSERT([tabView htmlOutputViewForIdentifier:[NSUUID UUID] busy:NO] == nil);

	view.reusable = NO; // a refreshing command keeps its view to itself
	OAK_ASSERT([tabView htmlOutputViewForIdentifier:command busy:NO] == nil);
}

void test_stopping_with_nothing_running_completes_at_once ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	add_view(tabView);

	__block NSInteger result = -1;
	[tabView stopRunningCommandsWithCompletionHandler:^(BOOL didStopAll){ result = didStopAll; }];
	OAK_ASSERT_EQ(result, 1);
}

static OakHTMLOutputTabView* strip_in_window ()
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 600, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSZeroRect];
	window.contentView = tabView;
	return tabView;
}

// A drop from another strip moves the view over without it ever leaving a window, so its refresher lives on
void test_a_tab_dropped_on_another_strip_moves_there ()
{
	[NSApplication sharedApplication];
	OutputTabsDelegate* delegate = [OutputTabsDelegate new];
	OakHTMLOutputTabView* source = strip_in_window();
	OakHTMLOutputTabView* dest   = strip_in_window();
	source.delegate = delegate;
	OakHTMLOutputView* moving = add_view(source);
	OakHTMLOutputView* staying = add_view(source);
	OakHTMLOutputView* existing = add_view(dest);
	[delegate watchView:moving];
	OAK_ASSERT(moving.window == source.window);

	OAK_ASSERT([dest performDropOfTabItem:moving.viewIdentifier fromTabBar:source.tabBarView index:0 toTabBar:dest.tabBarView index:0 operation:NSDragOperationMove]);
	OAK_ASSERT(moving.window == dest.window);
	OAK_ASSERT([dest.htmlOutputViews isEqualToArray:(@[ moving, existing ])]);
	OAK_ASSERT(dest.selectedHTMLOutputView == moving);
	OAK_ASSERT([source.htmlOutputViews isEqualToArray:(@[ staying ])]);
	OAK_ASSERT(source.selectedHTMLOutputView == staying);
	OAK_ASSERT_EQ(delegate.lostWindowCount, 0);
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 0);

	[dest performDropOfTabItem:staying.viewIdentifier fromTabBar:source.tabBarView index:0 toTabBar:dest.tabBarView index:2 operation:NSDragOperationMove];
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 1); // the source strip emptied
	OAK_ASSERT([dest.htmlOutputViews isEqualToArray:(@[ moving, existing, staying ])]);

	[source.window close];
	[dest.window close];
}

void test_a_tab_dropped_on_its_own_strip_reorders ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* a = add_view(tabView);
	OakHTMLOutputView* b = add_view(tabView);
	OakHTMLOutputView* c = add_view(tabView);

	OAK_ASSERT([tabView performDropOfTabItem:a.viewIdentifier fromTabBar:tabView.tabBarView index:0 toTabBar:tabView.tabBarView index:3 operation:NSDragOperationMove]);
	OAK_ASSERT([tabView.htmlOutputViews isEqualToArray:(@[ b, c, a ])]);
	OAK_ASSERT(tabView.selectedHTMLOutputView == a);

	[tabView performDropOfTabItem:c.viewIdentifier fromTabBar:tabView.tabBarView index:1 toTabBar:tabView.tabBarView index:0 operation:NSDragOperationMove];
	OAK_ASSERT([tabView.htmlOutputViews isEqualToArray:(@[ c, b, a ])]);
}

void test_a_tab_let_go_outside_any_strip_tears_off_into_a_window ()
{
	[NSApplication sharedApplication];
	OutputTabsDelegate* delegate = [OutputTabsDelegate new];
	OakHTMLOutputTabView* source = strip_in_window();
	OakHTMLOutputView* moving  = add_view(source);
	OakHTMLOutputView* staying = add_view(source);
	[delegate watchView:moving];

	[source tabBarView:source.tabBarView didEndDraggingTabItem:moving.viewIdentifier atScreenPoint:NSMakePoint(300, 300) operation:NSDragOperationNone];
	OAK_ASSERT([source.htmlOutputViews isEqualToArray:(@[ staying ])]);
	OAK_ASSERT(moving.window != nil && moving.window != source.window);
	OAK_ASSERT([moving.window.delegate isKindOfClass:[HTMLOutputWindowController class]]);
	OAK_ASSERT_EQ(delegate.lostWindowCount, 0);
	HTMLOutputWindowController* controller = (HTMLOutputWindowController*)moving.window.delegate;
	OAK_ASSERT([controller.tabView.htmlOutputViews isEqualToArray:(@[ moving ])]);

	// a drop that some strip took ends with a move, not a tear-off
	[source tabBarView:source.tabBarView didEndDraggingTabItem:staying.viewIdentifier atScreenPoint:NSMakePoint(300, 300) operation:NSDragOperationMove];
	OAK_ASSERT([source.htmlOutputViews isEqualToArray:(@[ staying ])]);

	// the only tab of an output window stays put: nothing to tear off from
	[controller.tabView tabBarView:controller.tabView.tabBarView didEndDraggingTabItem:moving.viewIdentifier atScreenPoint:NSMakePoint(300, 300) operation:NSDragOperationNone];
	OAK_ASSERT(moving.window == controller.window);

	[controller close];
	[source.window close];
}
