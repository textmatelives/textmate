@class OakCommand;
@class OakDocument;

typedef NS_OPTIONS(NSUInteger, OakCommandRefresherOptions) {
	OakCommandRefresherDocumentAsInput   = (1 << 0),
	OakCommandRefresherDocumentDidChange = (1 << 1),
	OakCommandRefresherDocumentDidSave   = (1 << 2),
	OakCommandRefresherDocumentDidClose  = (1 << 3),
};

@interface OakCommandRefresher : NSResponder
+ (OakCommandRefresher*)scheduleRefreshForCommand:(OakCommand*)aCommand document:(OakDocument*)document window:(NSWindow*)window options:(OakCommandRefresherOptions)options variables:(std::map<std::string, std::string> const&)variables;
+ (OakCommandRefresher*)findRefresherForCommandUUID:(NSUUID*)anIdentifier document:(OakDocument*)document window:(NSWindow*)window;
- (void)bringHTMLOutputToFront:(id)sender;

// Render another document in the same output view, browser style: the view
// gets a new page and history entry, and refreshes now follow that document.
// Returns NO when the command cannot take the document as input.
- (BOOL)showDocument:(OakDocument*)document variables:(std::map<std::string, std::string> const&)variables;
- (void)teardown;
@property (nonatomic, readonly) OakCommand* command;
@end
