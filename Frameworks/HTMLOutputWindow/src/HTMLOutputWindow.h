#import <HTMLOutput/HTMLOutput.h>
#import "OakHTMLOutputTabView.h"

// A window of HTML output tabs. The tab bar sits in the title bar, as in the document window.
@interface HTMLOutputWindowController : NSWindowController
@property (nonatomic, readonly) OakHTMLOutputTabView* tabView;
@property (nonatomic, readonly) OakHTMLOutputView* htmlOutputView; // the selected tab's view
- (instancetype)initWithIdentifier:(NSUUID*)anIdentifier;
- (OakHTMLOutputView*)newHTMLOutputView; // opens a new tab and selects it
@end
