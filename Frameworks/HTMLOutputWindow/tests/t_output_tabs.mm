#import <document/OakDocument.h>
#import <Preferences/Keys.h>
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
	OAK_ASSERT(tabView.tabStripView.superview == tabView);
	OAK_ASSERT(tabView.tabBarView.superview == tabView.tabStripView);
	tabView.hostsTabBar = NO;
	OAK_ASSERT(tabView.tabStripView.superview == nil);
	tabView.hostsTabBar = YES;
	OAK_ASSERT(tabView.tabStripView.superview == tabView);
}

// The window shows one tab per output view and its title follows the selected one
void test_the_output_window_hosts_tabs ()
{
	[NSApplication sharedApplication];
	HTMLOutputWindowController* controller = [[HTMLOutputWindowController alloc] initWithIdentifier:[NSUUID UUID]];
	OakHTMLOutputView* first = controller.htmlOutputView;
	OAK_ASSERT(first != nil);
	OAK_ASSERT_EQ(controller.tabView.htmlOutputViews.count, 1);
	OAK_ASSERT(controller.tabView.tabStripView.superview != controller.tabView); // the strip sits in the title bar

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

// The whole strip can move to another container at once, in order, keeping every view on screen
void test_all_tabs_move_to_another_strip_together ()
{
	[NSApplication sharedApplication];
	OutputTabsDelegate* delegate = [OutputTabsDelegate new];
	OakHTMLOutputTabView* source = strip_in_window();
	OakHTMLOutputTabView* dest   = strip_in_window();
	source.delegate = delegate;
	OakHTMLOutputView* a = add_view(source);
	OakHTMLOutputView* b = add_view(source);
	OakHTMLOutputView* c = add_view(dest);
	[source setSelectedHTMLOutputView:a];
	[delegate watchView:a];
	[delegate watchView:b];

	[source moveHTMLOutputViewsToTabView:dest];
	OAK_ASSERT([dest.htmlOutputViews isEqualToArray:(@[ c, a, b ])]);
	OAK_ASSERT(dest.selectedHTMLOutputView == a); // the selection travels with the strip
	OAK_ASSERT_EQ(source.htmlOutputViews.count, 0);
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 1);
	OAK_ASSERT_EQ(delegate.lostWindowCount, 0);

	[source.window close];
	[dest.window close];
}

// A view remembers which document its page was produced for, so a strip can bring that page forward for the document
void test_a_view_is_found_by_the_document_it_shows ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* a = add_view(tabView);
	OakHTMLOutputView* b = add_view(tabView);
	[b loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]] environment:{ { "TM_FILEPATH", "/tmp/notes.md" } } autoScrolls:NO];

	OAK_ASSERT([b.documentPath isEqualToString:@"/tmp/notes.md"]);
	OAK_ASSERT(a.documentPath == nil);
	OAK_ASSERT([tabView htmlOutputViewForDocumentPath:@"/tmp/notes.md"] == b);
	OAK_ASSERT([tabView htmlOutputViewForDocumentPath:@"/tmp/other.md"] == nil);
	OAK_ASSERT([tabView htmlOutputViewForDocumentPath:nil] == nil);

	// the strip names the document on the tab and shows its path in the tooltip
	OAK_ASSERT([[tabView tabBarView:tabView.tabBarView pathForIndex:1] isEqualToString:@"/tmp/notes.md"]);
	OAK_ASSERT([[tabView tabBarView:tabView.tabBarView titleForIndex:1] hasPrefix:@"notes.md"]);
	OAK_ASSERT([[tabView tabBarView:tabView.tabBarView pathForIndex:0] isEqualToString:@""]);
}

static void follow_documents (BOOL flag)
{
	[NSUserDefaults.standardUserDefaults setVolatileDomain:(flag ? @{ kUserDefaultsHTMLOutputFollowsDocumentKey: @YES } : @{ }) forName:NSArgumentDomain];
}

// With output tabs following their document, the tabs produced for a closing document go with it, unless a command still runs there
void test_a_documents_tabs_close_with_it ()
{
	follow_documents(YES);
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* other  = add_view(tabView);
	OakHTMLOutputView* forDoc = add_view(tabView);
	[other  loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]] environment:{ { "TM_FILEPATH", "/tmp/other.rb" } } autoScrolls:NO];
	[forDoc loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]] environment:{ { "TM_FILEPATH", "/tmp/script.rb" } } autoScrolls:NO];

	OakDocument* document = [OakDocument documentWithPath:@"/tmp/script.rb"];
	[NSNotificationCenter.defaultCenter postNotificationName:OakDocumentWillCloseNotification object:document];
	OAK_ASSERT([tabView.htmlOutputViews isEqualToArray:(@[ other ])]);
	follow_documents(NO);
}

// Without the preference, tabs are independent of documents and stay
void test_tabs_stay_when_not_following_documents ()
{
	follow_documents(NO);
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* forDoc = add_view(tabView);
	[forDoc loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]] environment:{ { "TM_FILEPATH", "/tmp/script.rb" } } autoScrolls:NO];

	[NSNotificationCenter.defaultCenter postNotificationName:OakDocumentWillCloseNotification object:[OakDocument documentWithPath:@"/tmp/script.rb"]];
	OAK_ASSERT([tabView.htmlOutputViews isEqualToArray:(@[ forDoc ])]);
}

// The output tab shortcuts cycle the strip, and a selection made by hand is announced so a document can follow it
void test_output_tabs_cycle_and_announce_a_choice ()
{
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	OakHTMLOutputView* a = add_view(tabView);
	OakHTMLOutputView* b = add_view(tabView);
	OakHTMLOutputView* c = add_view(tabView);

	__block NSMutableArray* announced = [NSMutableArray array];
	id token = [NSNotificationCenter.defaultCenter addObserverForName:OakHTMLOutputTabViewDidSelectViewNotification object:tabView queue:nil usingBlock:^(NSNotification* notification){
		[announced addObject:notification.userInfo[@"view"]];
	}];

	[tabView selectNextOutputTab:nil];
	OAK_ASSERT(tabView.selectedHTMLOutputView == a); // wraps around from the last
	[tabView selectPreviousOutputTab:nil];
	OAK_ASSERT(tabView.selectedHTMLOutputView == c);
	[tabView selectPreviousOutputTab:nil];
	OAK_ASSERT(tabView.selectedHTMLOutputView == b);
	OAK_ASSERT([announced isEqualToArray:(@[ a, c, b ])]);

	[tabView setSelectedHTMLOutputView:a]; // a selection made by code is not announced
	OAK_ASSERT_EQ(announced.count, 3);

	[NSNotificationCenter.defaultCenter removeObserver:token];
}

void test_close_all_output_tabs_empties_the_strip ()
{
	OutputTabsDelegate* delegate = [OutputTabsDelegate new];
	OakHTMLOutputTabView* tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	tabView.delegate = delegate;
	add_view(tabView);
	add_view(tabView);
	add_view(tabView);

	[tabView closeAllOutputTabs:nil];
	OAK_ASSERT_EQ(tabView.htmlOutputViews.count, 0);
	OAK_ASSERT_EQ(delegate.removedLastViewCount, 1);
}

// Closing the tab that holds the focus must hand it to the tab that takes its place,
// or the next ⌘W reaches the window and closes every remaining tab with it
void test_closing_the_focused_tab_hands_focus_to_the_next ()
{
	[NSApplication sharedApplication];
	OakHTMLOutputTabView* tabView = strip_in_window();
	OakHTMLOutputView* first  = add_view(tabView);
	OakHTMLOutputView* second = add_view(tabView);
	[tabView setSelectedHTMLOutputView:first];
	OAK_ASSERT([tabView.window makeFirstResponder:first.webView]);

	[tabView removeHTMLOutputView:first];
	OAK_ASSERT_EQ(tabView.selectedHTMLOutputView, second);
	OAK_ASSERT([tabView.window.firstResponder isKindOfClass:[NSView class]]);
	OAK_ASSERT([(NSView*)tabView.window.firstResponder isDescendantOf:second]);
}

// Closing a tab must not take the focus if it was not in that tab to begin with
void test_closing_an_unfocused_tab_leaves_the_focus_alone ()
{
	[NSApplication sharedApplication];
	OakHTMLOutputTabView* tabView = strip_in_window();
	OakHTMLOutputView* first  = add_view(tabView);
	OakHTMLOutputView* second = add_view(tabView);
	[tabView setSelectedHTMLOutputView:first];
	OAK_ASSERT([tabView.window makeFirstResponder:tabView.window]);

	[tabView removeHTMLOutputView:first];
	OAK_ASSERT_EQ(tabView.selectedHTMLOutputView, second);
	OAK_ASSERT_EQ(tabView.window.firstResponder, tabView.window);
}
