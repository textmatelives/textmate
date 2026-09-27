#import "HTMLOutputWindow.h"
#import <OakAppKit/OakAppKit.h>
#import <OakFoundation/NSString Additions.h>
#import <command/runner.h>
#import <ns/ns.h>
#import <oak/debug.h>

@interface HTMLOutputWindowController () <NSWindowDelegate, OakHTMLOutputTabViewDelegate>
@property (nonatomic, readwrite) OakHTMLOutputTabView* tabView;
@property (nonatomic) NSTitlebarAccessoryViewController* titlebarViewController;
@property (nonatomic) HTMLOutputWindowController* retainedSelf;
@end

@implementation HTMLOutputWindowController
+ (NSSet*)keyPathsForValuesAffectingHtmlOutputView
{
	return [NSSet setWithObjects:@"tabView.selectedHTMLOutputView", nil];
}

- (instancetype)init
{
	NSRect rect = [[NSScreen mainScreen] visibleFrame];
	rect = NSIntegralRect(NSInsetRect(rect, NSWidth(rect) / 3, NSHeight(rect) / 5));
	NSWindow* window = [[NSWindow alloc] initWithContentRect:rect styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable) backing:NSBackingStoreBuffered defer:NO];

	if(self = [super initWithWindow:window])
	{
		self.window  = window;
		self.tabView = [[OakHTMLOutputTabView alloc] initWithFrame:NSZeroRect];
		self.tabView.delegate    = self;
		self.tabView.hostsTabBar = NO;

		_titlebarViewController = [[NSTitlebarAccessoryViewController alloc] init];
		self.tabView.tabBarView.frameSize = self.tabView.tabBarView.intrinsicContentSize;
		_titlebarViewController.view = self.tabView.tabBarView;
		_titlebarViewController.fullScreenMinHeight = NSHeight(self.tabView.tabBarView.frame);
		[self.window addTitlebarAccessoryViewController:_titlebarViewController];

		[self.window bind:NSTitleBinding toObject:self.tabView withKeyPath:@"selectedHTMLOutputView.mainFrameTitle" options:nil];
		[self.window bind:NSDocumentEditedBinding toObject:self.tabView withKeyPath:@"selectedHTMLOutputView.runningCommand" options:nil];
		[self.window setContentView:self.tabView];
		[self.window setDelegate:self];
		[self.window setReleasedWhenClosed:NO];
		[self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary];
	}
	return self;
}

- (instancetype)initWithIdentifier:(NSUUID*)anIdentifier
{
	if(self = [self init])
	{
		self.window.frameAutosaveName = [NSString stringWithFormat:@"HTML output for %@", anIdentifier.UUIDString];
		[self newHTMLOutputView];
	}
	return self;
}

- (OakHTMLOutputView*)htmlOutputView
{
	return self.tabView.selectedHTMLOutputView;
}

- (OakHTMLOutputView*)newHTMLOutputView
{
	OakHTMLOutputView* view = [[OakHTMLOutputView alloc] initWithFrame:NSZeroRect];
	[self.tabView addHTMLOutputView:view];
	return view;
}

- (void)showWindow:(id)sender
{
	self.retainedSelf = self;
	[super showWindow:sender];
}

- (void)cancelOperation:(id)sender
{
	[self.window performClose:sender];
}

- (void)htmlOutputTabViewDidRemoveLastView:(OakHTMLOutputTabView*)tabView
{
	[self.window close];
}

- (BOOL)windowShouldClose:(id)sender
{
	if(![self.tabView.htmlOutputViews filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isRunningCommand == YES"]].count)
		return YES;

	// Stop the running commands one at a time, then close; a refused stop keeps the window
	[self.tabView stopRunningCommandsWithCompletionHandler:^(BOOL didStopAll){
		if(didStopAll)
		{
			[self.window orderOut:self];
			[self.window close];
		}
	}];
	return NO;
}

- (void)windowWillClose:(NSNotification*)notification
{
	[self performSelector:@selector(setRetainedSelf:) withObject:nil afterDelay:0];
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self.window unbind:NSTitleBinding];
	[self.window unbind:NSDocumentEditedBinding];
	self.window.delegate = nil;
}
@end
