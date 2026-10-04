#import "FileBrowserView.h"
#import "FileBrowserOutlineView.h"
#import "OFB/OFBHeaderView.h"
#import "OFB/OFBActionsView.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface FileBrowserView () <NSAccessibilityGroup>
@property (nonatomic) CGFloat baseTopInset;
@property (nonatomic) NSScrollView* scrollView;
@end

@implementation FileBrowserView
- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.accessibilityRole  = NSAccessibilityGroupRole;
		self.accessibilityLabel = @"File browser";

		_headerView    = [[OFBHeaderView alloc] initWithFrame:NSZeroRect];
		_actionsView   = [[OFBActionsView alloc] initWithFrame:NSZeroRect];

		_outlineView = [[FileBrowserOutlineView alloc] initWithFrame:NSZeroRect];
		_outlineView.accessibilityLabel       = @"Files";
		_outlineView.allowsMultipleSelection  = YES;
		_outlineView.autoresizesOutlineColumn = NO;
		_outlineView.focusRingType            = NSFocusRingTypeNone;
		_outlineView.headerView               = nil;

		if(@available(macos 11.0, *))
		{
			_outlineView.style = NSTableViewStylePlain;
			_outlineView.floatsGroupRows = NO;
		}

		[_outlineView setDraggingSourceOperationMask:NSDragOperationLink|NSDragOperationMove|NSDragOperationCopy forLocal:YES];
		[_outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
		[_outlineView registerForDraggedTypes:@[ NSFilenamesPboardType ]];

		NSTableColumn* tableColumn = [[NSTableColumn alloc] init];
		[_outlineView addTableColumn:tableColumn];
		[_outlineView setOutlineTableColumn:tableColumn];
		[_outlineView sizeLastColumnToFit];

		_scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		_scrollView.borderType            = NSNoBorder;
		_scrollView.documentView          = _outlineView;
		_scrollView.hasHorizontalScroller = NO;
		_scrollView.hasVerticalScroller   = YES;
		_scrollView.autohidesScrollers    = YES;

		NSDictionary* views = @{
			@"header":  _headerView,
			@"files":   _scrollView,
			@"actions": _actionsView,
		};

		OakAddAutoLayoutViewsToSuperview(views.allValues, self);
		[_headerView removeFromSuperview];
		[self addSubview:_headerView positioned:NSWindowAbove relativeTo:nil];

		OakSetupKeyViewLoop(@[ self, _headerView, _outlineView, _actionsView ]);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[files(==header,==actions)]|" options:0 metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[header]-(>=0)-[actions]"     options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[files][actions]|"            options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];

		_baseTopInset = _scrollView.contentInsets.top;
		_scrollView.automaticallyAdjustsContentInsets = NO;
		[self updateTopInset];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];

		_outlineView.backgroundColor = NSColor.clearColor;
		_scrollView.drawsBackground  = NO;

		NSVisualEffectView* sidebarBackground = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
		sidebarBackground.material     = NSVisualEffectMaterialSidebar;
		sidebarBackground.blendingMode = NSVisualEffectBlendingModeBehindWindow;
		sidebarBackground.state        = NSVisualEffectStateFollowsWindowActiveState;
		sidebarBackground.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:sidebarBackground positioned:NSWindowBelow relativeTo:nil];
		NSDictionary* bgViews = @{ @"bg": sidebarBackground };
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[bg]|" options:0 metrics:nil views:bgViews]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[bg]|" options:0 metrics:nil views:bgViews]];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

// The header floats above the list, so the list is inset by the header’s height.
- (void)updateTopInset
{
	NSEdgeInsets insets = _scrollView.contentInsets;
	insets.top = _baseTopInset + _headerView.fittingSize.height;
	_scrollView.contentInsets = insets;
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateTopInset];
}
@end
