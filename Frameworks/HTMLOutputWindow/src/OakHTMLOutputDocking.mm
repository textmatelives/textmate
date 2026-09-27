#import "OakHTMLOutputDocking.h"

static CGFloat const kDockBand = 0.3; // the outer third along each axis snaps to that edge

OakHTMLOutputDockEdge OakHTMLOutputDockEdgeForPoint (NSRect bounds, NSPoint point)
{
	if(!NSPointInRect(point, bounds) || NSIsEmptyRect(bounds))
		return OakHTMLOutputDockEdgeNone;

	CGFloat const x = (point.x - NSMinX(bounds)) / NSWidth(bounds);
	CGFloat const y = (point.y - NSMinY(bounds)) / NSHeight(bounds);
	if(y < kDockBand && (x >= kDockBand && x <= 1 - kDockBand || y < std::min(x, 1 - x)))
		return OakHTMLOutputDockEdgeBottom;
	if(x < kDockBand)
		return OakHTMLOutputDockEdgeLeft;
	if(x > 1 - kDockBand)
		return OakHTMLOutputDockEdgeRight;
	return OakHTMLOutputDockEdgeNone;
}

NSRect OakHTMLOutputDockRectForEdge (NSRect bounds, OakHTMLOutputDockEdge edge)
{
	switch(edge)
	{
		case OakHTMLOutputDockEdgeBottom: return NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), round(NSHeight(bounds) * kDockBand));
		case OakHTMLOutputDockEdgeLeft:   return NSMakeRect(NSMinX(bounds), NSMinY(bounds), round(NSWidth(bounds) * kDockBand), NSHeight(bounds));
		case OakHTMLOutputDockEdgeRight:  return NSMakeRect(NSMaxX(bounds) - round(NSWidth(bounds) * kDockBand), NSMinY(bounds), round(NSWidth(bounds) * kDockBand), NSHeight(bounds));
		case OakHTMLOutputDockEdgeNone:   break;
	}
	return NSZeroRect;
}
