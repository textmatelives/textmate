#import <oak/misc.h>

@class OakHTMLOutputTabView;

typedef NS_ENUM(NSInteger, OakHTMLOutputDockEdge) {
	OakHTMLOutputDockEdgeNone = 0,
	OakHTMLOutputDockEdgeBottom,
	OakHTMLOutputDockEdgeRight,
	OakHTMLOutputDockEdgeLeft,
};

// Which edge of a dock area a dragged strip would snap to at the point, in the area's coordinates; none in the middle
OakHTMLOutputDockEdge OakHTMLOutputDockEdgeForPoint (NSRect bounds, NSPoint point);

// The part of the area the strip would cover at that edge, for highlighting
NSRect OakHTMLOutputDockRectForEdge (NSRect bounds, OakHTMLOutputDockEdge edge);

// A window whose delegate can take a strip of output tabs at one of its edges
@protocol OakHTMLOutputDockTarget <NSObject>
- (NSView*)htmlOutputDockAreaView;
- (void)dockHTMLOutputTabView:(OakHTMLOutputTabView*)tabView atEdge:(OakHTMLOutputDockEdge)edge;
@end
