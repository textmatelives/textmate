#import "OakHTMLOutputView.h"
#import "browser/HOStatusBar.h"
#import "helpers/HOAutoScroll.h"
#import "helpers/HOJSBridge.h"
#import "helpers/HOWKScriptMessageHandler.h"
#import "helpers/OakLocalLinkPolicy.h"
#import "helpers/OakHTMLOutputPageCache.h"
#import "helpers/OakHTMLOutputRequestMetadata.h"
#import "helpers/OakSystemCommandURLSchemeHandler.h"
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/NSAlert Additions.h>
#import <oak/debug.h>

@interface HOStatusBar (BusyAndProgressProperties) <HOJSBridgeDelegate>
@end

@interface OakHTMLOutputView ()
{
	std::map<std::string, std::map<std::string, std::string>> _environmentByPage; // pages in the history and the environment each was produced with
}
@property (nonatomic, getter = isRunningCommand, readwrite) BOOL runningCommand;
@property (nonatomic) HOAutoScroll* autoScrollHelper;
@property (nonatomic) std::map<std::string, std::string> environment;
@property (nonatomic) NSArray* pendingScrollPosition;
@property (nonatomic, getter = isVisible) BOOL visible;
@end

static std::string page_key (NSURL* url)
{
	NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	components.fragment = nil;
	return std::string(components.URL.absoluteString.UTF8String ?: "");
}

@implementation OakHTMLOutputView
+ (NSSet*)keyPathsForValuesAffectingMainFrameTitle
{
	return [NSSet setWithObjects:@"webView.title", nil];
}

- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_reusable = YES;
	}
	return self;
}

- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag
{
	if(flag)
		self.autoScrollHelper = [[HOAutoScroll alloc] initWithWebView:self.webView];

	self.environment = anEnvironment;
	_environmentByPage[page_key(aRequest.URL)] = anEnvironment;

	// Pass environment to the script message handler so TextMate.system() uses correct env
	[self.scriptMessageHandler setEnvironment:anEnvironment];
	[self.scriptMessageHandler setDelegate:self.statusBar];

	// Pass environment to the system command handler for synchronous TextMate.system(cmd, null)
	self.systemCommandHandler.environment = anEnvironment;

	// Read commandIdentifier from metadata registry instead of NSURLProtocol property
	OakHTMLOutputRequestMetadata* metadata = [OakHTMLOutputRequestMetadata metadataForURLString:aRequest.URL.absoluteString];
	self.commandIdentifier = metadata.commandIdentifier;
	self.runningCommand = self.commandIdentifier != nil;

	[self willChangeValueForKey:@"mainFrameTitle"];
	[self.webView loadRequest:aRequest];
	[self didChangeValueForKey:@"mainFrameTitle"];
}

- (void)stopLoadingWithUserInteraction:(BOOL)askUserFlag completionHandler:(void(^)(BOOL didStop))handler
{
	OakHTMLOutputRequestMetadata* metadata = [OakHTMLOutputRequestMetadata metadataForURLString:self.webView.URL.absoluteString];
	if(metadata.command)
	{
		NSAlert* alert = askUserFlag ? [NSAlert tmAlertWithMessageText:[NSString stringWithFormat:@"Stop \u201C%@\u201D?", metadata.processName] informativeText:@"The job that the task is performing will not be completed." buttons:@"Stop", @"Cancel", nil] : nil;

		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:@"OakCommandDidTerminateNotification" object:metadata.command queue:nil usingBlock:^(NSNotification* notification){
			if(alert)
				[self.window endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
			handler(YES);
			[NSNotificationCenter.defaultCenter removeObserver:token];
		}];

		if(alert)
		{
			[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
				if(returnCode == NSAlertFirstButtonReturn) /* "Stop" */
				{
					[self.webView stopLoading];
				}
				else
				{
					handler(NO);
					[NSNotificationCenter.defaultCenter removeObserver:token];
				}
			}];
		}
		else
		{
			[self.webView stopLoading];
		}
	}
	else
	{
		handler(YES);
	}
}

- (void)setContent:(NSString*)someHTML
{
	// Save scroll position via JavaScript
	[self.webView evaluateJavaScript:@"[window.scrollX, window.scrollY]" completionHandler:^(NSArray* result, NSError* error){
		if([result isKindOfClass:[NSArray class]] && result.count == 2)
			self.pendingScrollPosition = result;
	}];

	// Rewrite file:// to tm-file:// in href/src attributes (same as streaming path)
	// but preserve file:// inside txmt:// links
	NSMutableString* rewritten = [someHTML mutableCopy];
	NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:
		@"((?:href|src)\\s*=\\s*[\"'])file://" options:0 error:nil];
	NSArray<NSTextCheckingResult*>* matches = [regex matchesInString:rewritten options:0 range:NSMakeRange(0, rewritten.length)];
	for(NSTextCheckingResult* match in [matches reverseObjectEnumerator])
	{
		NSRange fullRange = match.range;
		NSString* prefix = [rewritten substringWithRange:[match rangeAtIndex:1]];
		NSUInteger searchStart = fullRange.location > 50 ? fullRange.location - 50 : 0;
		NSRange searchRange = NSMakeRange(searchStart, fullRange.location - searchStart);
		if([rewritten rangeOfString:@"txmt://" options:0 range:searchRange].location != NSNotFound)
			continue;
		[rewritten replaceCharactersInRange:fullRange withString:[prefix stringByAppendingString:@"tm-file://"]];
	}

	// Refresh in place. Loading an HTML string would replace the history entry with a document that
	// cannot be revisited, so for a page we streamed the new content is served under its own URL instead.
	std::string const key = page_key(self.webView.URL);
	if(_environmentByPage.count(key))
	{
		[OakHTMLOutputPageCache.sharedCache setData:[rewritten dataUsingEncoding:NSUTF8StringEncoding] forKey:[NSString stringWithCxxString:key]];
		[self.webView reload];
	}
	else
	{
		[self.webView loadHTMLString:rewritten baseURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
	}
}

- (NSString*)mainFrameTitle
{
	if(OakIsEmptyString(self.webView.title))
	{
		OakHTMLOutputRequestMetadata* metadata = [OakHTMLOutputRequestMetadata metadataForURLString:self.webView.URL.absoluteString];
		if(metadata.processName)
			return metadata.processName;
	}
	return self.webView.title;
}

- (void)viewDidMoveToWindow
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowWillCloseNotification object:nil];
	if(self.window)
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:self.window];
	self.visible = self.window ? YES : NO;
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	self.visible = NO;
}

// ========================
// = WKNavigationDelegate =
// ========================

- (void)webView:(WKWebView*)webView didStartProvisionalNavigation:(WKNavigation*)navigation
{
	self.statusBar.busy = YES;
	[self setUpdatesProgress:!self.isRunningCommand];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;
	[self restoreEnvironmentForPage:webView];

	// Re-inject environment into the JS bridge after navigation (e.g., goBack/goForward)
	if(!self.disableJavaScriptAPI)
	{
		NSString* scheme = webView.URL.scheme;
		if([@[@"tm-file", @"file", @"x-txmt-filehandle"] containsObject:scheme])
		{
			[self.scriptMessageHandler setEnvironment:_environment];
			[self.scriptMessageHandler setDelegate:self.statusBar];
			self.systemCommandHandler.environment = _environment;
		}
	}

	// Restore scroll position if pending
	if(self.pendingScrollPosition)
	{
		NSString* js = [NSString stringWithFormat:@"window.scrollTo(%@, %@)",
			self.pendingScrollPosition[0], self.pendingScrollPosition[1]];
		[webView evaluateJavaScript:js completionHandler:nil];
		self.pendingScrollPosition = nil;
	}

	[super webView:webView didFinishNavigation:navigation];
}

// Back and forward return to pages that other documents produced: bring back the environment that made each
- (void)restoreEnvironmentForPage:(WKWebView*)webView
{
	auto page = _environmentByPage.find(page_key(webView.URL));
	if(page != _environmentByPage.end() && page->second != _environment)
	{
		_environment = page->second;
		if(self.documentDidChangeHandler)
		{
			auto path = _environment.find("TM_FILEPATH");
			self.documentDidChangeHandler(path != _environment.end() ? [NSString stringWithCxxString:path->second] : nil);
		}
	}

	std::set<std::string> history;
	WKBackForwardList* list = webView.backForwardList;
	for(WKBackForwardListItem* item in list.backList)
		history.insert(page_key(item.URL));
	for(WKBackForwardListItem* item in list.forwardList)
		history.insert(page_key(item.URL));
	if(list.currentItem)
		history.insert(page_key(list.currentItem.URL));
	for(auto it = _environmentByPage.begin(); it != _environmentByPage.end(); )
		it = history.count(it->first) ? std::next(it) : _environmentByPage.erase(it);
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;
	[super webView:webView didFailProvisionalNavigation:navigation withError:error];
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;
	[super webView:webView didFailNavigation:navigation withError:error];
}

// ==========================================================
// = Navigation Policy: Intercept txmt:// and local files =
// ==========================================================

- (void)openTxMtURL:(NSURL*)url
{
	auto projectUUID = _environment.find("TM_PROJECT_UUID");
	if(projectUUID != _environment.end())
		url = [NSURL URLWithString:[[url absoluteString] stringByAppendingFormat:@"&project=%@", [NSString stringWithCxxString:projectUUID->second]]];
	[NSApp sendAction:@selector(handleTxMtURL:) to:nil from:url];
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	NSURL* url = navigationAction.request.URL;
	NSString* scheme = url.scheme;

	// Local files: the web view shows what it can render, a clicked link to anything else opens in TextMate
	if([@[@"tm-file", @"file"] containsObject:scheme])
	{
		auto documentPath = _environment.find("TM_FILEPATH");
		BOOL linkActivated = navigationAction.navigationType == WKNavigationTypeLinkActivated;
		switch(OakLocalLinkActionForURL(url, linkActivated, documentPath != _environment.end() ? [NSString stringWithCxxString:documentPath->second] : nil))
		{
			case OakLocalLinkActionLoad:
				decisionHandler(WKNavigationActionPolicyAllow);
			break;

			case OakLocalLinkActionOpen:
				if(!(self.localFileHandler && self.localFileHandler(url.path)))
					[self openTxMtURL:OakTxMtOpenURLForPath(url.path)];
				decisionHandler(WKNavigationActionPolicyCancel);
			break;

			case OakLocalLinkActionScroll:
				[webView evaluateJavaScript:OakScrollToFragmentScript(url.fragment) completionHandler:nil];
				decisionHandler(WKNavigationActionPolicyCancel);
			break;
		}
		return;
	}

	// Allow our other custom schemes
	if([@[@"x-txmt-filehandle", @"tm-system", @"about"] containsObject:scheme])
	{
		decisionHandler(WKNavigationActionPolicyAllow);
		return;
	}

	// Handle txmt:// internally
	if([scheme isEqualToString:@"txmt"])
	{
		[self openTxMtURL:url];
		decisionHandler(WKNavigationActionPolicyCancel);
		return;
	}

	// Handle http/https -- allow in-page navigation, open external links externally
	if([@[@"http", @"https"] containsObject:scheme])
	{
		if(navigationAction.navigationType == WKNavigationTypeLinkActivated)
		{
			[NSWorkspace.sharedWorkspace openURL:url];
			decisionHandler(WKNavigationActionPolicyCancel);
		}
		else
		{
			decisionHandler(WKNavigationActionPolicyAllow);
		}
		return;
	}

	// Unknown scheme -- open externally
	[NSWorkspace.sharedWorkspace openURL:url];
	decisionHandler(WKNavigationActionPolicyCancel);
}

// ====================
// = Printing Support =
// ====================

- (IBAction)printDocument:(id)sender
{
	NSPrintInfo* printInfo = [NSPrintInfo sharedPrintInfo];
	NSPrintOperation* printOp = [self.webView printOperationWithPrintInfo:printInfo];
	[[printOp printPanel] setOptions:[[printOp printPanel] options] | NSPrintPanelShowsPaperSize | NSPrintPanelShowsOrientation];
	[printOp runOperationModalForWindow:self.window delegate:nil didRunSelector:NULL contextInfo:nil];
}
@end
