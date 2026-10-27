#import <FileBrowser/FileBrowserViewController.h>

// ⌘← and ⌘→ in the file browser send goBack:/goForward: straight from the
// outline view’s key equivalent handler, with no menu validation in between,
// so the actions themselves must refuse to step outside the history.

static NSException* ExceptionFrom (void(^block)())
{
	@try { block(); }
	@catch(NSException* e) { return e; }
	return nil;
}

void test_go_back_with_no_history_is_a_noop ()
{
	FileBrowserViewController* controller = [[FileBrowserViewController alloc] init];
	OAK_ASSERT(!controller.canGoBack);
	NSException* e = ExceptionFrom(^{ [controller goBack:nil]; });
	OAK_ASSERT_EQ(e ? std::string([e.reason UTF8String]) : std::string(), std::string());
	OAK_ASSERT(!controller.canGoBack);
	OAK_ASSERT(!controller.canGoForward);
}

void test_go_forward_with_no_history_is_a_noop ()
{
	FileBrowserViewController* controller = [[FileBrowserViewController alloc] init];
	OAK_ASSERT(!controller.canGoForward);
	NSException* e = ExceptionFrom(^{ [controller goForward:nil]; });
	OAK_ASSERT_EQ(e ? std::string([e.reason UTF8String]) : std::string(), std::string());
	OAK_ASSERT(!controller.canGoForward);
	OAK_ASSERT(!controller.canGoBack);
}

// A saved history index past the last entry must land on the last entry,
// not one past it.
void test_restored_history_index_is_clamped_to_the_last_entry ()
{
	NSKeyedArchiver* archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
	[archiver encodeObject:@[ @{ @"url": [NSURL fileURLWithPath:NSTemporaryDirectory()] } ] forKey:@"history"];
	[archiver encodeInteger:7 forKey:@"historyIndex"];
	[archiver finishEncoding];

	FileBrowserViewController* controller = [[FileBrowserViewController alloc] init];
	NSKeyedUnarchiver* unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archiver.encodedData error:nil];
	NSException* e = ExceptionFrom(^{ [controller restoreStateWithCoder:unarchiver]; });
	OAK_ASSERT_EQ(e ? std::string([e.reason UTF8String]) : std::string(), std::string());
	OAK_ASSERT(!controller.canGoBack);
	OAK_ASSERT(!controller.canGoForward);
}
