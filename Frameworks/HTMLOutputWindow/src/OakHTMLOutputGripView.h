#import <oak/misc.h>

@class OakHTMLOutputTabView;

// The handle at the left end of an output tab strip. Dragging it carries the whole strip:
// to an edge of a document window, where it snaps in, or to nowhere, where it becomes a window.
@interface OakHTMLOutputGripView : NSView
@property (nonatomic, weak) OakHTMLOutputTabView* tabView;
@end
