#import <HTMLOutput/HTMLOutput.h>
#import "OakHTMLOutputTabView.h"

// A window of HTML output tabs. The tab bar sits in the title bar, as in the document window.
@interface HTMLOutputWindowController : NSWindowController
@property (nonatomic, readonly) OakHTMLOutputTabView* tabView;
@property (nonatomic, readonly) OakHTMLOutputView* htmlOutputView; // the selected tab's view
- (instancetype)init; // an empty window, for tabs handed over from elsewhere
- (instancetype)initWithIdentifier:(NSUUID*)anIdentifier; // a window with one tab, its frame saved under the command
- (OakHTMLOutputView*)newHTMLOutputView; // opens a new tab and selects it
@end
