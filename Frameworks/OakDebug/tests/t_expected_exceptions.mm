#import <OakDebug/OakExpectedException.h>
#import <AppKit/AppKit.h>
#import "ExceptionRecorder.h"

// AppKit raises, and catches itself, an exception when it has to break a
// constraint. TextMate's handler sees it before AppKit catches it (issue #94).
void test_unsatisfiable_layout_exception_is_expected ()
{
	NSExceptionHandler* handler = NSExceptionHandler.defaultExceptionHandler;
	NSUInteger oldMask = handler.exceptionHandlingMask;
	id oldDelegate = handler.delegate;

	ExceptionRecorder* recorder = [ExceptionRecorder new];
	handler.exceptionHandlingMask = NSLogAndHandleEveryExceptionMask;
	handler.delegate = recorder;

	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
	NSView* view = [NSView new];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	[window.contentView addSubview:view];
	[NSLayoutConstraint activateConstraints:@[
		[view.widthAnchor constraintEqualToConstant:100],
		[view.widthAnchor constraintEqualToConstant:150],
	]];
	[window.contentView layoutSubtreeIfNeeded];

	handler.delegate = oldDelegate;
	handler.exceptionHandlingMask = oldMask;

	OAK_ASSERT_EQ(recorder.exceptions.count, 1);
	OAK_ASSERT(OakExceptionIsExpected(recorder.exceptions.firstObject));
}

void test_menu_accessibility_exception_is_expected ()
{
	NSException* exception = [NSException exceptionWithName:NSInvalidArgumentException reason:@"-[NSMenu accessibilityPerformAction:]: unrecognized selector sent to instance 0x600000000000" userInfo:nil];
	OAK_ASSERT(OakExceptionIsExpected(exception));
}

void test_spell_server_timeout_exception_is_expected ()
{
	NSException* exception = [NSException exceptionWithName:@"NSXPCSpellServerTimeoutException" reason:@"Spell server connection timeout sending findMisspelledWordInString" userInfo:nil];
	OAK_ASSERT(OakExceptionIsExpected(exception));
	OAK_ASSERT(!OakExceptionIsExpected([NSException exceptionWithName:NSGenericException reason:@"Spell server connection timeout sending findMisspelledWordInString" userInfo:nil]));
}

void test_other_exceptions_are_not_expected ()
{
	OAK_ASSERT(!OakExceptionIsExpected([NSException exceptionWithName:NSGenericException reason:@"something else went wrong" userInfo:nil]));
	OAK_ASSERT(!OakExceptionIsExpected([NSException exceptionWithName:NSInternalInconsistencyException reason:@"layout constraints are not satisfiable." userInfo:nil]));
	OAK_ASSERT(!OakExceptionIsExpected([NSException exceptionWithName:NSRangeException reason:@"index 3 beyond bounds" userInfo:nil]));
}
