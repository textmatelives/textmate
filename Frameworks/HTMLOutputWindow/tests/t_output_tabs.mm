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
	HTMLOutputWindowController* controller = [[HTMLOutputWindowController alloc] init];
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
