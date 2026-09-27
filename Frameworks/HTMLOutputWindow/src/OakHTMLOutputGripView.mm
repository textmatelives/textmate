#import "OakHTMLOutputGripView.h"
#import "OakHTMLOutputTabView.h"
#import "OakHTMLOutputDocking.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface OakHTMLOutputGripView ()
@property (nonatomic) NSWindow* overlay; // marks the edge the strip would snap to
@end

@implementation OakHTMLOutputGripView
- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.toolTip = @"Drag to move the output tabs to another edge, or out into a window";
		self.accessibilityLabel = @"Move output tabs";
	}
	return self;
}

- (NSSize)intrinsicContentSize
{
	return NSMakeSize(OakScaledUIMetric(18), NSViewNoIntrinsicMetric);
}

- (void)drawRect:(NSRect)aRect
{
	// Two columns of three dots, centred
	CGFloat const dot = OakScaledUIMetric(2), gap = OakScaledUIMetric(3);
	NSPoint const center = NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
	[NSColor.tertiaryLabelColor set];
	for(int col = -1; col <= 1; col += 2)
	{
		for(int row = -1; row <= 1; ++row)
			[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x + col * gap / 2 - dot / 2, center.y + row * gap - dot / 2, dot, dot)] fill];
	}
}

- (void)resetCursorRects
{
	[self addCursorRect:self.bounds cursor:NSCursor.openHandCursor];
}

- (BOOL)mouseDownCanMoveWindow
{
	return NO;
}

// ============
// = Dragging =
// ============

- (id <OakHTMLOutputDockTarget>)dockTargetAtScreenPoint:(NSPoint)aPoint edge:(OakHTMLOutputDockEdge*)outEdge areaRect:(NSRect*)outRect
{
	for(NSWindow* window in NSApp.orderedWindows)
	{
		if(!window.isVisible || window.isMiniaturized || ![window.delegate conformsToProtocol:@protocol(OakHTMLOutputDockTarget)] || !NSPointInRect(aPoint, window.frame))
			continue;

		id <OakHTMLOutputDockTarget> target = (id <OakHTMLOutputDockTarget>)window.delegate;
		NSView* area = target.htmlOutputDockAreaView;
		NSPoint local = [area convertPoint:[window convertPointFromScreen:aPoint] fromView:nil];
		*outEdge = OakHTMLOutputDockEdgeForPoint(area.bounds, local);
		NSRect rect = OakHTMLOutputDockRectForEdge(area.bounds, *outEdge);
		*outRect = NSIsEmptyRect(rect) ? NSZeroRect : [window convertRectToScreen:[area convertRect:rect toView:nil]];
		return target;
	}
	*outEdge = OakHTMLOutputDockEdgeNone;
	*outRect = NSZeroRect;
	return nil;
}

- (void)showOverlayAtScreenRect:(NSRect)aRect inWindow:(NSWindow*)aWindow
{
	if(NSIsEmptyRect(aRect))
		return [self hideOverlay];

	if(!_overlay)
	{
		_overlay = [[NSWindow alloc] initWithContentRect:aRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		_overlay.backgroundColor      = [NSColor.controlAccentColor colorWithAlphaComponent:0.3];
		_overlay.opaque               = NO;
		_overlay.hasShadow            = NO;
		_overlay.ignoresMouseEvents   = YES;
		_overlay.releasedWhenClosed   = NO;
	}

	if(_overlay.parentWindow != aWindow)
	{
		[_overlay.parentWindow removeChildWindow:_overlay];
		[aWindow addChildWindow:_overlay ordered:NSWindowAbove];
	}
	[_overlay setFrame:aRect display:YES];
	[_overlay orderFront:nil];
}

- (void)hideOverlay
{
	[_overlay.parentWindow removeChildWindow:_overlay];
	[_overlay orderOut:nil];
}

- (void)mouseDown:(NSEvent*)anEvent
{
	OakHTMLOutputTabView* tabView = self.tabView;
	if(!tabView || anEvent.type != NSEventTypeLeftMouseDown)
		return [super mouseDown:anEvent];

	NSPoint const mouseDownPos = anEvent.locationInWindow;
	BOOL didDrag = NO;
	id <OakHTMLOutputDockTarget> target = nil;
	OakHTMLOutputDockEdge edge = OakHTMLOutputDockEdgeNone;
	NSPoint screenPoint = NSZeroPoint;

	[NSCursor.closedHandCursor push];
	while(true)
	{
		anEvent = [NSApp nextEventMatchingMask:(NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp) untilDate:NSDate.distantFuture inMode:NSEventTrackingRunLoopMode dequeue:YES];
		if(anEvent.type == NSEventTypeLeftMouseUp)
			break;

		NSPoint pos = anEvent.locationInWindow;
		if(!didDrag && hypot(mouseDownPos.x - pos.x, mouseDownPos.y - pos.y) < 4)
			continue;
		didDrag = YES;

		screenPoint = [self.window convertPointToScreen:pos];
		NSRect rect;
		target = [self dockTargetAtScreenPoint:screenPoint edge:&edge areaRect:&rect];
		[self showOverlayAtScreenRect:rect inWindow:[(id)target window]];
	}
	[NSCursor pop];
	[self hideOverlay];

	if(!didDrag)
		return;

	if(target)
	{
		if(edge != OakHTMLOutputDockEdgeNone)
			[target dockHTMLOutputTabView:tabView atEdge:edge];
	}
	else
	{
		[tabView tearOffAllHTMLOutputViewsAtScreenPoint:screenPoint];
	}
}
@end
