#import "AboutWindowController.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

static NSString* const kUserDefaultsLastLaunchedVersionKey = @"lastLaunchedVersion";

@interface AboutWindowController () <NSWindowDelegate, NSToolbarDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, readonly) NSArray<NSString*>* segmentLabels;
@property (nonatomic) NSToolbar* toolbar;
@property (nonatomic) NSSegmentedControl* segmentedControl;
@property (nonatomic) WKWebView* webView;
@property (nonatomic) NSString* selectedPage;
@end

@implementation AboutWindowController
+ (instancetype)sharedInstance
{
	static AboutWindowController* sharedInstance = [self new];
	return sharedInstance;
}

+ (NSWindow*)hostWindowForUpdateNotice
{
	for(NSWindow* window in NSApp.orderedWindows)
	{
		if(window.isVisible && !window.isSheet && window.canBecomeKeyWindow)
			return window;
	}
	return nil;
}

+ (void)beginUpdateNoticeForVersion:(NSString*)currentVersion onWindow:(NSWindow*)window
{
	NSAlert* alert        = [[NSAlert alloc] init];
	alert.messageText     = @"TextMate Has Been Updated";
	alert.informativeText = [NSString stringWithFormat:@"You are now running version %@.", currentVersion];

	[alert addButtonWithTitle:@"Changelog"]; // first added is the default
	[alert addButtonWithTitle:@"Cancel"];

	// A sheet, not -runModal. The mate server accepts connections from a
	// dispatch source on the main queue, and the modal loop does not drain
	// that queue. mate launches us without activation, so a modal alert also
	// sits hidden while mate blocks in read().
	[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		if(returnCode == NSAlertFirstButtonReturn)
			[AboutWindowController.sharedInstance showChangesWindow:nil];
	}];
}

+ (void)presentUpdateNoticeForVersion:(NSString*)currentVersion
{
	if(NSWindow* window = [self hostWindowForUpdateNotice])
	{
		[self beginUpdateNoticeForVersion:currentVersion onWindow:window];
		return;
	}

	// mate starts us with -disableNewDocumentAtStartup, so the document
	// window does not exist yet. Wait until it does; the server can accept
	// the connection in the meantime.
	__block id token = nil;
	token = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
		NSWindow* window = note.object;
		if(![window isKindOfClass:[NSWindow class]] || !window.isVisible || window.isSheet || !window.canBecomeKeyWindow)
			return;
		[NSNotificationCenter.defaultCenter removeObserver:token];
		[self beginUpdateNoticeForVersion:currentVersion onWindow:window];
	}];
}

+ (void)showUpdateNoticeIfNeeded
{
	// Offers the changelog once, the first time a newly installed version is
	// run. It does not open the release notes by itself: an app that throws its
	// own changelog at you on launch is a nuisance, so the window only appears
	// if the notice is answered with Changelog.
	//
	// The trigger is the running version, not the content of the release notes.
	// A digest of CHANGELOG.html would also fire when the notes changed without
	// the version doing so, which is not what "you have been updated" means.
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;

	NSString* currentVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if(!currentVersion.length)
		return;

	NSString* lastVersion = [defaults stringForKey:kUserDefaultsLastLaunchedVersionKey];
	[defaults setObject:currentVersion forKey:kUserDefaultsLastLaunchedVersionKey];

	// Nothing to announce on a first run — no version was left behind to have
	// come from — nor when relaunching the version already recorded. Any change
	// counts, in either direction: the update dialog offers downgrades too, so
	// the wording states the version rather than claiming an upgrade.
	if(!lastVersion.length || [lastVersion isEqualToString:currentVersion])
		return;

	// After this method returns, so a document window from launch (or from the
	// mate connection that is about to be accepted) can host the sheet.
	dispatch_async(dispatch_get_main_queue(), ^{
		[self presentUpdateNoticeForVersion:currentVersion];
	});
}

- (id)init
{
	NSRect visibleRect = [[NSScreen mainScreen] visibleFrame];
	NSRect rect = NSMakeRect(0, 0, std::min<CGFloat>(700, NSWidth(visibleRect)), std::min<CGFloat>(800, NSHeight(visibleRect)));

	CGFloat dy = NSHeight(visibleRect) - NSHeight(rect);

	rect.origin.y = round(NSMinY(visibleRect) + dy*3/4);
	rect.origin.x = NSMaxY(visibleRect) - NSMaxY(rect);

	NSWindow* win = [[NSPanel alloc] initWithContentRect:rect styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
	if((self = [super initWithWindow:win]))
	{
		_segmentLabels    = @[ @"About", @"Changes", @"Legal", @"Contributions" ];
		_segmentedControl = [NSSegmentedControl segmentedControlWithLabels:_segmentLabels trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(takeSelectedSegmentFrom:)];

		self.toolbar = [[NSToolbar alloc] initWithIdentifier:@"About TextMate"];
		[self.toolbar setAllowsUserCustomization:NO];
		[self.toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
		[self.toolbar setDelegate:self];
		[win setToolbar:self.toolbar];

		[win setFrameAutosaveName:@"BundlesReleaseNotes"];
		[win setDelegate:self];
		[win setAutorecalculatesKeyViewLoop:YES];
		[win setHidesOnDeactivate:NO];
		[win setTitleVisibility:NSWindowTitleHidden];

		WKWebViewConfiguration* webConfig = [[WKWebViewConfiguration alloc] init];
		[webConfig.userContentController addScriptMessageHandler:self name:@"textmate"];

		self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:webConfig];
		self.webView.navigationDelegate = self;
		[self.webView setValue:@NO forKey:@"drawsBackground"];

		if(NSURL* url = [NSBundle.mainBundle URLForResource:@"WKWebView" withExtension:@"js"])
		{
			NSError* error;
			if(NSMutableString* jsBridge = [NSMutableString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error])
			{
				NSDictionary* variables = @{
					@"version":   [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
					@"copyright": [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSHumanReadableCopyright"],
				};

				[variables enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL* stop){
					[jsBridge appendFormat:@"TextMate.%@ = %@;\n", key, [self javaScriptEscapedString:[value isEqual:[NSNull null]] ? @"" : value]];
				}];

				WKUserScript* script = [[WKUserScript alloc] initWithSource:jsBridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
				[self.webView.configuration.userContentController addUserScript:script];
			}
			else if(error)
			{
				os_log_error(OS_LOG_DEFAULT, "Failed to load WKWebView.js: %{public}@", error.localizedDescription);
			}
		}
		else
		{
			os_log_error(OS_LOG_DEFAULT, "Failed to locate WKWebView.js in application bundle");
		}

		[self.webView.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
		[self.webView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

		[win setContentView:self.webView];
	}
	return self;
}

- (void)dealloc
{
	[_webView.configuration.userContentController removeAllUserScripts];
	_webView.navigationDelegate = nil;
	[_webView stopLoading];
}

- (void)showAboutWindow:(id)sender
{
	self.selectedPage = @"About";
	[self showWindow:self];
}

- (void)showChangesWindow:(id)sender
{
	self.selectedPage = @"Changes";
	[self showWindow:self];
}

- (void)takeSelectedSegmentFrom:(id)sender
{
	if(sender == _segmentedControl)
		self.selectedPage = _segmentLabels[_segmentedControl.selectedSegment];
	else if([sender respondsToSelector:@selector(representedObject)])
		self.selectedPage = [sender representedObject];
}

- (void)setSelectedPage:(NSString*)pageName
{
	if(_selectedPage == pageName || [_selectedPage isEqualToString:pageName])
		return;
	_selectedPage = pageName;

	NSDictionary* pages = @{
		@"About":         @"About/About",
		@"Changes":       @"About/CHANGELOG",
		@"Legal":         @"About/Legal",
		@"Contributions": @"About/Contributions"
	};

	if(NSString* file = pages[pageName])
	{
		if(NSURL* url = [NSBundle.mainBundle URLForResource:file withExtension:@"html"])
			[self.webView loadRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60]];

		_segmentedControl.selectedSegment = [_segmentLabels indexOfObject:pageName];
	}
}

- (void)selectPageAtRelativeOffset:(NSInteger)offset
{
	NSUInteger index = [_segmentLabels indexOfObject:self.selectedPage];
	if(index != NSNotFound)
		self.selectedPage = _segmentLabels[(index + _segmentLabels.count + offset) % _segmentLabels.count];
}

- (IBAction)selectNextTab:(id)sender     { [self selectPageAtRelativeOffset:+1]; }
- (IBAction)selectPreviousTab:(id)sender { [self selectPageAtRelativeOffset:-1]; }

// ====================
// = Toolbar Delegate =
// ====================

- (NSToolbarItem*)toolbar:(NSToolbar*)aToolbar itemForItemIdentifier:(NSString*)anIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem* res = [[NSToolbarItem alloc] initWithItemIdentifier:anIdentifier];
	if(![anIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
		res.view = _segmentedControl;
	return res;
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)aToolbar
{
	return [self toolbarDefaultItemIdentifiers:aToolbar];
}

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)aToolbar
{
	return @[ NSToolbarFlexibleSpaceItemIdentifier, @"TMSegmentedControlIdentifier", NSToolbarFlexibleSpaceItemIdentifier ];
}

- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(![[self window] isKeyWindow])
	{
		[aMenu addItemWithTitle:@"No Tabs" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	for(NSUInteger i = 0; i < _segmentLabels.count; ++i)
	{
		NSString* label = _segmentLabels[i];
		NSMenuItem* item = [aMenu addItemWithTitle:label action:@selector(takeSelectedSegmentFrom:) keyEquivalent:i < 9 ? [NSString stringWithFormat:@"%c", '1' + (char)i] : @""];
		[item setRepresentedObject:label];
		[item setTarget:self];
		[item setState:i == _segmentedControl.selectedSegment ? NSControlStateValueOn : NSControlStateValueOff];
	}
}

// =============
// = WKWebView =
// =============

- (NSString*)javaScriptEscapedString:(NSString*)src
{
	static NSRegularExpression* const regex = [NSRegularExpression regularExpressionWithPattern:@"['\"\\\\]" options:0 error:nil];
	NSString* escaped = src ? [regex stringByReplacingMatchesInString:src options:0 range:NSMakeRange(0, src.length) withTemplate:@"\\\\$0"] : @"";
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
	return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	if(![navigationAction.request.URL.scheme isEqualToString:@"file"] && [NSWorkspace.sharedWorkspace openURL:navigationAction.request.URL])
			decisionHandler(WKNavigationActionPolicyCancel);
	else	decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
	if(![message.name isEqualToString:@"textmate"])
	{
		os_log_error(OS_LOG_DEFAULT, "Message received for unknown message handler: %{public}@", message.name);
		return;
	}

	NSString* command     = message.body[@"command"];
	NSDictionary* payload = message.body[@"payload"];

	if([command isEqualToString:@"log"])
	{
		if([payload[@"level"] isEqualToString:@"error"])
		{
			static os_log_t log = os_log_create("com.macromates.JavaScript", "error");
			os_log_error(log, "%{public}@:%{public}@: %{public}@", payload[@"filename"], payload[@"lineno"], payload[@"message"]);
		}
		else
		{
			static os_log_t log = os_log_create("com.macromates.JavaScript", "log");
			os_log(log, "%{public}@: %{public}@", self.webView.title, payload[@"message"]);
		}
	}
}
@end
