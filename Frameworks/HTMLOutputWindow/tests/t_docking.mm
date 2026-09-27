#import <HTMLOutputWindow/OakHTMLOutputDocking.h>

static std::string edge_at (CGFloat x, CGFloat y)
{
	switch(OakHTMLOutputDockEdgeForPoint(NSMakeRect(0, 0, 1000, 500), NSMakePoint(x, y)))
	{
		case OakHTMLOutputDockEdgeNone:   return "none";
		case OakHTMLOutputDockEdgeBottom: return "bottom";
		case OakHTMLOutputDockEdgeRight:  return "right";
		case OakHTMLOutputDockEdgeLeft:   return "left";
	}
	return "?";
}

// The outer third along each axis snaps; the corners go to whichever edge is nearer, the middle to nothing
void test_dock_edges_by_position ()
{
	OAK_ASSERT_EQ(edge_at(500, 250), "none");
	OAK_ASSERT_EQ(edge_at(500,  50), "bottom");
	OAK_ASSERT_EQ(edge_at( 50, 250), "left");
	OAK_ASSERT_EQ(edge_at(950, 250), "right");
	OAK_ASSERT_EQ(edge_at(500, 450), "none");   // no top edge
	OAK_ASSERT_EQ(edge_at( 30,   5), "bottom"); // closer to the bottom than the left, in relative terms
	OAK_ASSERT_EQ(edge_at( 10, 100), "left");
	OAK_ASSERT_EQ(edge_at(-1,  250), "none");   // outside
}

void test_dock_rects_cover_the_snapping_band ()
{
	NSRect bounds = NSMakeRect(0, 0, 1000, 500);
	OAK_ASSERT(NSEqualRects(OakHTMLOutputDockRectForEdge(bounds, OakHTMLOutputDockEdgeBottom), NSMakeRect(0, 0, 1000, 150)));
	OAK_ASSERT(NSEqualRects(OakHTMLOutputDockRectForEdge(bounds, OakHTMLOutputDockEdgeLeft),   NSMakeRect(0, 0, 300, 500)));
	OAK_ASSERT(NSEqualRects(OakHTMLOutputDockRectForEdge(bounds, OakHTMLOutputDockEdgeRight),  NSMakeRect(700, 0, 300, 500)));
	OAK_ASSERT(NSIsEmptyRect(OakHTMLOutputDockRectForEdge(bounds, OakHTMLOutputDockEdgeNone)));
}
