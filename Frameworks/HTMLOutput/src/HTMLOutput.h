#include <oak/misc.h>

@interface OakHTMLOutputView : NSView
- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag;
- (void)stopLoadingWithUserInteraction:(BOOL)askUserFlag completionHandler:(void(^)(BOOL didStop))handler;
- (void)setContent:(NSString*)someHTML;

@property (nonatomic) NSUUID* commandIdentifier; // UUID from initial load request
@property (nonatomic, getter = isRunningCommand, readonly) BOOL runningCommand;
@property (nonatomic, getter = isVisible, readonly) BOOL visible;
@property (nonatomic, getter = isReusable) BOOL reusable;
@property (nonatomic) BOOL disableJavaScriptAPI;

// Asked before a clicked link to a local file the web view cannot render is opened in the editor.
// Return YES to take the link, e.g. to render the file in this view.
@property (nonatomic, copy) BOOL(^localFileHandler)(NSString* path);

// Called after back or forward lands on a page that was produced for another document.
@property (nonatomic, copy) void(^documentDidChangeHandler)(NSString* path);

// Read-only access to the webview is given to allow reading page title, etc.
@property (nonatomic, readonly) WKWebView* webView;
@property (nonatomic, readonly) BOOL needsNewWebView; // retained, always NO
@end
