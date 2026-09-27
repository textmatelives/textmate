#import "OakHTMLOutputTabView.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>

static void* kTabTitleObservationContext = &kTabTitleObservationContext;

@interface OakHTMLOutputTabView () <OakTabBarViewDataSource, OakTabBarViewDelegate>
@property (nonatomic, readwrite) OakTabBarView* tabBarView;
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

		_contentView = [[NSView alloc] initWithFrame:NSZeroRect];

		OakAddAutoLayoutViewsToSuperview(@[ _tabBarView, _contentView ], self);
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
	NSDictionary* views = @{ @"tabBar": _tabBarView, @"content": _contentView };
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[content]|" options:0 metrics:nil views:views]];
	if(_hostsTabBar)
	{
		if(_tabBarView.superview != self)
			[self addSubview:_tabBarView];
		[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tabBar]|" options:0 metrics:nil views:views]];
		[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tabBar][content]|" options:0 metrics:nil views:views]];
		[constraints addObject:[NSLayoutConstraint constraintWithItem:_tabBarView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:_tabBarView.intrinsicContentSize.height]];
	}
	else
	{
		if(_tabBarView.superview == self)
			[_tabBarView removeFromSuperview];
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
	if([_views containsObject:aView])
		return [self setSelectedHTMLOutputView:aView];

	[_views addObject:aView];
	aView.hidden = YES;
	OakAddAutoLayoutViewsToSuperview(@[ aView ], _contentView);
	[_contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{ @"view": aView }]];
	[_contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{ @"view": aView }]];
	[self observeView:aView];

	[_tabBarView reloadData];
	[self setSelectedHTMLOutputView:aView];
}

- (void)removeHTMLOutputView:(OakHTMLOutputView*)aView
{
	NSUInteger index = [_views indexOfObject:aView];
	if(index == NSNotFound)
		return;

	[self stopObservingView:aView];
	[_views removeObjectAtIndex:index];
	[aView removeFromSuperview];
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

// The selected tab closes on ⌘W; the window's own close button still closes the window
- (void)performClose:(id)sender
{
	if(_views.count > 1 && _selectedHTMLOutputView)
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
