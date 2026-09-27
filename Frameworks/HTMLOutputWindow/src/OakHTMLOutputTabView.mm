#import "OakHTMLOutputTabView.h"
#import "HTMLOutputWindow.h"
#import "OakHTMLOutputGripView.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>

static void* kTabTitleObservationContext = &kTabTitleObservationContext;

@interface OakHTMLOutputTabView ()
@property (nonatomic, readwrite) OakTabBarView* tabBarView;
@property (nonatomic, readwrite) NSView* tabStripView;
@property (nonatomic) OakHTMLOutputGripView* gripView;
@property (nonatomic) NSView* contentView;
@property (nonatomic) NSMutableArray<OakHTMLOutputView*>* views;
@property (nonatomic) NSArray<NSLayoutConstraint*>* layoutConstraints;
@end

@implementation OakHTMLOutputTabView
- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_views       = [NSMutableArray array];
		_hostsTabBar = YES;

		_tabBarView = [[OakTabBarView alloc] initWithFrame:NSZeroRect];
		_tabBarView.dataSource = self;
		_tabBarView.delegate   = self;
		_tabBarView.hidesNewTabButton = YES; // output tabs come from commands

		_gripView = [[OakHTMLOutputGripView alloc] initWithFrame:NSZeroRect];
		_gripView.tabView = self;

		_tabStripView = [[NSView alloc] initWithFrame:NSZeroRect];
		OakAddAutoLayoutViewsToSuperview(@[ _gripView, _tabBarView ], _tabStripView);
		[_tabStripView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[grip][tabBar]|" options:0 metrics:nil views:@{ @"grip": _gripView, @"tabBar": _tabBarView }]];
		[_tabStripView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[grip]|" options:0 metrics:nil views:@{ @"grip": _gripView }]];
		[_tabStripView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tabBar]|" options:0 metrics:nil views:@{ @"tabBar": _tabBarView }]];

		_contentView = [[NSView alloc] initWithFrame:NSZeroRect];

		OakAddAutoLayoutViewsToSuperview(@[ _tabStripView, _contentView ], self);
		[self updateLayout];
	}
	return self;
}

- (void)dealloc
{
	_tabBarView.dataSource = nil;
	_tabBarView.delegate   = nil;
	for(OakHTMLOutputView* view in _views)
		[self stopObservingView:view];
}

- (void)updateLayout
{
	if(_layoutConstraints)
		[NSLayoutConstraint deactivateConstraints:_layoutConstraints];

	NSMutableArray* constraints = [NSMutableArray array];
	NSDictionary* views = @{ @"tabBar": _tabStripView, @"content": _contentView };
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[content]|" options:0 metrics:nil views:views]];
	if(_hostsTabBar)
	{
		if(_tabStripView.superview != self)
			[self addSubview:_tabStripView];
		[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tabBar]|" options:0 metrics:nil views:views]];
		[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tabBar][content]|" options:0 metrics:nil views:views]];
		[constraints addObject:[NSLayoutConstraint constraintWithItem:_tabStripView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:_tabBarView.intrinsicContentSize.height]];
	}
	else
	{
		if(_tabStripView.superview == self)
			[_tabStripView removeFromSuperview];
		[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[content]|" options:0 metrics:nil views:views]];
	}
	[NSLayoutConstraint activateConstraints:constraints];
	_layoutConstraints = constraints;
}

- (void)setHostsTabBar:(BOOL)flag
{
	if(_hostsTabBar == flag)
		return;
	_hostsTabBar = flag;
	[self updateLayout];
}

- (NSArray<OakHTMLOutputView*>*)htmlOutputViews
{
	return [_views copy];
}

// =========
// = Views =
// =========

- (void)addHTMLOutputView:(OakHTMLOutputView*)aView
{
	[self insertHTMLOutputView:aView atIndex:_views.count];
}

- (void)insertHTMLOutputView:(OakHTMLOutputView*)aView atIndex:(NSUInteger)anIndex
{
	NSUInteger current = [_views indexOfObject:aView];
	if(current != NSNotFound) // reorder
	{
		[_views removeObjectAtIndex:current];
		[_views insertObject:aView atIndex:MIN(anIndex > current ? anIndex-1 : anIndex, _views.count)];
		[_tabBarView reloadData];
		return [self setSelectedHTMLOutputView:aView];
	}

	// Take the view over first, so it never leaves the window hierarchy: its refresher stops when it does
	OakHTMLOutputTabView* previousOwner = [OakHTMLOutputTabView ownerOfHTMLOutputView:aView];
	[_views insertObject:aView atIndex:MIN(anIndex, _views.count)];
	aView.hidden = YES;
	OakAddAutoLayoutViewsToSuperview(@[ aView ], _contentView);
	[_contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{ @"view": aView }]];
	[_contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{ @"view": aView }]];
	[self observeView:aView];
	[previousOwner detachHTMLOutputView:aView];

	[_tabBarView reloadData];
	[self setSelectedHTMLOutputView:aView];
}

+ (OakHTMLOutputTabView*)ownerOfHTMLOutputView:(OakHTMLOutputView*)aView
{
	for(NSView* view = aView.superview; view; view = view.superview)
	{
		if([view isKindOfClass:[OakHTMLOutputTabView class]] && [[(OakHTMLOutputTabView*)view views] containsObject:aView])
			return (OakHTMLOutputTabView*)view;
	}
	return nil;
}

- (void)removeHTMLOutputView:(OakHTMLOutputView*)aView
{
	if([_views containsObject:aView])
	{
		[self detachHTMLOutputView:aView];
		[aView removeFromSuperview];
	}
}

// Forgets the view without taking it off screen; another strip may already hold it
- (void)detachHTMLOutputView:(OakHTMLOutputView*)aView
{
	NSUInteger index = [_views indexOfObject:aView];
	if(index == NSNotFound)
		return;

	[self stopObservingView:aView];
	[_views removeObjectAtIndex:index];
	[_tabBarView reloadData];

	if(_selectedHTMLOutputView == aView)
	{
		_selectedHTMLOutputView = nil;
		if(_views.count)
			[self setSelectedHTMLOutputView:_views[MIN(index, _views.count-1)]];
	}

	if(_views.count == 0 && [_delegate respondsToSelector:@selector(htmlOutputTabViewDidRemoveLastView:)])
		[_delegate htmlOutputTabViewDidRemoveLastView:self];
}

- (HTMLOutputWindowController*)windowControllerAtScreenPoint:(NSPoint)aPoint
{
	HTMLOutputWindowController* controller = [[HTMLOutputWindowController alloc] init];
	NSRect frame = controller.window.frame;
	frame.origin = NSMakePoint(aPoint.x - 40, aPoint.y - NSHeight(frame) + 20); // the dragged tab lands under the pointer
	[controller.window setFrameOrigin:frame.origin];
	return controller;
}

- (HTMLOutputWindowController*)tearOffHTMLOutputView:(OakHTMLOutputView*)aView atScreenPoint:(NSPoint)aPoint
{
	if(![_views containsObject:aView])
		return nil;

	HTMLOutputWindowController* controller = [self windowControllerAtScreenPoint:aPoint];
	[controller.tabView addHTMLOutputView:aView];
	[controller showWindow:self];
	return controller;
}

- (void)moveHTMLOutputViewsToTabView:(OakHTMLOutputTabView*)aTabView
{
	OakHTMLOutputView* selected = _selectedHTMLOutputView;
	for(OakHTMLOutputView* view in [_views copy])
		[aTabView addHTMLOutputView:view];
	if(selected)
		[aTabView setSelectedHTMLOutputView:selected];
}

- (HTMLOutputWindowController*)tearOffAllHTMLOutputViewsAtScreenPoint:(NSPoint)aPoint
{
	if(_views.count == 0 || [self.window.delegate isKindOfClass:[HTMLOutputWindowController class]])
		return nil; // an output window is already on its own

	id <OakHTMLOutputTabViewDelegate> delegate = _delegate;
	HTMLOutputWindowController* controller = [self windowControllerAtScreenPoint:aPoint];
	[self moveHTMLOutputViewsToTabView:controller.tabView];
	[controller showWindow:self];
	if([delegate respondsToSelector:@selector(htmlOutputTabView:didTearOffIntoWindowController:)])
		[delegate htmlOutputTabView:self didTearOffIntoWindowController:controller];
	return controller;
}

- (OakHTMLOutputView*)htmlOutputViewForIdentifier:(NSUUID*)aCommandIdentifier busy:(BOOL)busyFlag
{
	for(OakHTMLOutputView* view in _views)
	{
		if(view.isReusable && !view.needsNewWebView && [view.commandIdentifier isEqual:aCommandIdentifier] && view.isRunningCommand == busyFlag)
			return view;
	}
	return nil;
}

- (void)stopRunningCommandsWithCompletionHandler:(void(^)(BOOL didStopAll))handler
{
	NSArray<OakHTMLOutputView*>* running = [_views filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isRunningCommand == YES"]];
	[self stopViews:running.objectEnumerator completionHandler:handler];
}

- (void)stopViews:(NSEnumerator<OakHTMLOutputView*>*)views completionHandler:(void(^)(BOOL didStopAll))handler
{
	OakHTMLOutputView* view = views.nextObject;
	if(!view)
		return handler(YES);

	[self setSelectedHTMLOutputView:view]; // the stop prompt is about this view
	[view stopLoadingWithUserInteraction:YES completionHandler:^(BOOL didStop){
		if(didStop)
				[self stopViews:views completionHandler:handler];
		else	handler(NO);
	}];
}

- (void)setSelectedHTMLOutputView:(OakHTMLOutputView*)aView
{
	if(aView && ![_views containsObject:aView])
		return;

	BOOL const hadFocus = _selectedHTMLOutputView && [self.window.firstResponder isKindOfClass:[NSView class]] && [(NSView*)self.window.firstResponder isDescendantOf:_selectedHTMLOutputView];

	_selectedHTMLOutputView = aView;
	for(OakHTMLOutputView* view in _views)
		view.hidden = view != aView;
	_tabBarView.selectedTabIndex = aView ? [_views indexOfObject:aView] : NSNotFound;

	if(hadFocus && aView)
		[self.window makeFirstResponder:aView.webView];
}

- (void)revealHTMLOutputView:(OakHTMLOutputView*)aView
{
	[self setSelectedHTMLOutputView:aView];
}

// ⌘W closes the selected tab; closing the last one closes the window or hides the pane, via the delegate
- (void)performClose:(id)sender
{
	if(_selectedHTMLOutputView)
			[self closeHTMLOutputView:_selectedHTMLOutputView];
	else	[self.window performClose:sender];
}

- (void)closeHTMLOutputView:(OakHTMLOutputView*)aView
{
	if(!aView.isRunningCommand)
		return [self removeHTMLOutputView:aView];

	__weak OakHTMLOutputTabView* weakSelf = self;
	[self setSelectedHTMLOutputView:aView]; // the stop prompt is a sheet about this view
	[aView stopLoadingWithUserInteraction:YES completionHandler:^(BOOL didStop){
		if(didStop)
			[weakSelf removeHTMLOutputView:aView];
	}];
}

// ==============
// = Tab titles =
// ==============

- (void)observeView:(OakHTMLOutputView*)aView
{
	[aView addObserver:self forKeyPath:@"mainFrameTitle" options:0 context:kTabTitleObservationContext];
	[aView addObserver:self forKeyPath:@"runningCommand" options:0 context:kTabTitleObservationContext];
}

- (void)stopObservingView:(OakHTMLOutputView*)aView
{
	[aView removeObserver:self forKeyPath:@"mainFrameTitle" context:kTabTitleObservationContext];
	[aView removeObserver:self forKeyPath:@"runningCommand" context:kTabTitleObservationContext];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == kTabTitleObservationContext)
			[_tabBarView reloadData];
	else	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// ===========================
// = OakTabBarViewDataSource =
// ===========================

- (NSUInteger)numberOfRowsInTabBarView:(OakTabBarView*)aTabBarView                     { return _views.count; }
- (NSString*)tabBarView:(OakTabBarView*)aTabBarView titleForIndex:(NSUInteger)anIndex  { return OakIsEmptyString(_views[anIndex].mainFrameTitle) ? @"Untitled" : _views[anIndex].mainFrameTitle; }
- (NSString*)tabBarView:(OakTabBarView*)aTabBarView pathForIndex:(NSUInteger)anIndex   { return @""; }
- (NSUUID*)tabBarView:(OakTabBarView*)aTabBarView UUIDForIndex:(NSUInteger)anIndex     { return _views[anIndex].viewIdentifier; }
- (BOOL)tabBarView:(OakTabBarView*)aTabBarView isEditedAtIndex:(NSUInteger)anIndex     { return _views[anIndex].isRunningCommand; }

// =========================
// = OakTabBarViewDelegate =
// =========================

- (BOOL)tabBarView:(OakTabBarView*)aTabBarView shouldSelectIndex:(NSUInteger)anIndex
{
	if(anIndex < _views.count)
		[self setSelectedHTMLOutputView:_views[anIndex]];
	return YES;
}

- (void)performCloseTab:(OakTabBarView*)sender
{
	NSUInteger index = sender.tag;
	if(index < _views.count)
		[self closeHTMLOutputView:_views[index]];
}

- (BOOL)performDropOfTabItem:(NSUUID*)tabItemUUID fromTabBar:(OakTabBarView*)sourceTabBar index:(NSUInteger)dragIndex toTabBar:(OakTabBarView*)destTabBar index:(NSUInteger)droppedIndex operation:(NSDragOperation)operation
{
	id source = sourceTabBar.delegate;
	if(![source isKindOfClass:[OakHTMLOutputTabView class]])
		return NO; // only output tabs can come here

	for(OakHTMLOutputView* view in [(OakHTMLOutputTabView*)source views])
	{
		if([view.viewIdentifier isEqual:tabItemUUID])
		{
			[self insertHTMLOutputView:view atIndex:droppedIndex];
			return YES;
		}
	}
	return NO;
}

- (void)tabBarView:(OakTabBarView*)aTabBarView didEndDraggingTabItem:(NSUUID*)tabItemUUID atScreenPoint:(NSPoint)aPoint operation:(NSDragOperation)operation
{
	if(operation != NSDragOperationNone)
		return;

	for(OakHTMLOutputView* view in [_views copy])
	{
		if(![view.viewIdentifier isEqual:tabItemUUID])
			continue;
		if(_views.count == 1 && [self.window.delegate isKindOfClass:[HTMLOutputWindowController class]])
			return; // already alone in its own window
		[self tearOffHTMLOutputView:view atScreenPoint:aPoint];
		return;
	}
}

- (void)performCloseOtherTabsXYZ:(OakTabBarView*)sender
{
	NSUInteger index = sender.tag;
	if(index >= _views.count)
		return;

	OakHTMLOutputView* keep = _views[index];
	for(OakHTMLOutputView* view in [_views copy])
	{
		if(view != keep && !view.isRunningCommand)
			[self removeHTMLOutputView:view];
	}
	[self setSelectedHTMLOutputView:keep];
}
@end
