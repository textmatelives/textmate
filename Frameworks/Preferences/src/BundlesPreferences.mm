#import "BundlesPreferences.h"
#import <BundlesManager/BundlesManager.h>
#import <OakFoundation/OakFoundation.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScopeBarView.h>

static NSUserInterfaceItemIdentifier const kTableColumnIdentifierInstalled   = @"Installed";
static NSUserInterfaceItemIdentifier const kTableColumnIdentifierBundleName  = @"BundleName";
static NSUserInterfaceItemIdentifier const kTableColumnIdentifierWebLink     = @"WebLink";
static NSUserInterfaceItemIdentifier const kTableColumnIdentifierUpdated     = @"Updated";
static NSUserInterfaceItemIdentifier const kTableColumnIdentifierDescription = @"Description";
static NSUserInterfaceItemIdentifier const kTableColumnIdentifierActions     = @"Actions";

@interface BundleInstallHelper : NSObject
@property (nonatomic) NSMutableSet* bundlesBeingInstalled;
@property (nonatomic) NSString* bundleInstallActivityText;
@property (nonatomic, getter = isBusy, readonly) BOOL busy;
@property (nonatomic, readonly) NSString* activityText;
@end

@implementation BundleInstallHelper
+ (instancetype)sharedInstance
{
	static BundleInstallHelper* sharedInstance = [self new];
	return sharedInstance;
}

+ (NSSet*)keyPathsForValuesAffectingBusy
{
	return [NSSet setWithObjects:@"bundlesBeingInstalled", nil];
}

+ (NSSet*)keyPathsForValuesAffectingActivityText
{
	return [NSSet setWithObjects:@"bundleInstallActivityText", nil];
}

- (instancetype)init
{
	if(self = [super init])
	{
		_bundlesBeingInstalled = [NSMutableSet set];
	}
	return self;
}

- (BOOL)isBusy
{
	return _bundlesBeingInstalled.count != 0;
}

- (NSString*)activityText
{
	if(_bundleInstallActivityText)
		return _bundleInstallActivityText;

	if(NSDate* date = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsLastBundleUpdateCheckKey])
	{
		NSString* dateString = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
#if defined(MAC_OS_X_VERSION_10_15) && (MAC_OS_X_VERSION_10_15 <= MAC_OS_X_VERSION_MAX_ALLOWED)
		if(@available(macos 10.15, *))
			dateString = -[date timeIntervalSinceNow] < 5 ? @"Just now" : [[[NSRelativeDateTimeFormatter alloc] init] localizedStringForDate:date relativeToDate:NSDate.now];
#endif
		return [NSString stringWithFormat:@"Bundle index last updated: %@", dateString];
	}

	return @"";
}

- (void)installBundle:(Bundle*)bundle
{
	if([_bundlesBeingInstalled containsObject:bundle])
		return;

	[self willChangeValueForKey:@"bundlesBeingInstalled"];
	[_bundlesBeingInstalled addObject:bundle];
	[self didChangeValueForKey:@"bundlesBeingInstalled"];

	self.bundleInstallActivityText = [NSString stringWithFormat:@"Installing ‘%@’ bundle…", bundle.name];

	[BundlesManager.sharedInstance installBundles:@[ bundle ] completionHandler:^(NSArray<Bundle*>* bundles){
		if(!bundle.installed)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Error installing ‘%@’ bundle.", bundle.name];
		else if(bundles.count == 1)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle.", bundle.name];
		else if(bundles.count == 2)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle and one dependency.", bundle.name];
		else
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle and %ld dependencies.", bundle.name, bundles.count-1];

		[self willChangeValueForKey:@"bundlesBeingInstalled"];
		[_bundlesBeingInstalled removeObject:bundle];
		[self didChangeValueForKey:@"bundlesBeingInstalled"];
	}];
}

- (void)uninstallBundle:(Bundle*)bundle
{
	[BundlesManager.sharedInstance uninstallBundle:bundle];
	self.bundleInstallActivityText = [NSString stringWithFormat:@"Uninstalled ‘%@’ bundle.", bundle.name];
}
@end

@interface Bundle (BundlesInstallPreferences)
@property (nonatomic) NSControlStateValue installedCellState;
@end

@implementation Bundle (BundlesInstallPreferences)
+ (NSSet*)keyPathsForValuesAffectingInstalledCellState
{
	return [NSSet setWithObjects:@"installed", @"bundleInstallHelper.bundlesBeingInstalled", nil];
}

- (BundleInstallHelper*)bundleInstallHelper
{
	return BundleInstallHelper.sharedInstance;
}

- (NSControlStateValue)installedCellState
{
	return [self.bundleInstallHelper.bundlesBeingInstalled containsObject:self] ? NSControlStateValueMixed : (self.isInstalled ? NSControlStateValueOn : NSControlStateValueOff);
}

- (void)setInstalledCellState:(NSControlStateValue)newValue
{
	if(self.installedCellState == NSControlStateValueOff && newValue != NSControlStateValueOff)
		[self.bundleInstallHelper installBundle:self];
	else if(self.installedCellState == NSControlStateValueOn && newValue != NSControlStateValueOn)
		[self.bundleInstallHelper uninstallBundle:self];
}
@end

// ================
// = Hover-highlight NSTableView subclass
// ================

@interface OakHoverTableView : NSTableView
@property (nonatomic) NSInteger hoveredRow;
@end

@implementation OakHoverTableView
{
	NSTrackingArea* _trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if(self = [super initWithFrame:frameRect])
		_hoveredRow = -1;
	return self;
}

- (void)updateTrackingAreas
{
	[super updateTrackingAreas];
	if(_trackingArea)
		[self removeTrackingArea:_trackingArea];
	_trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
		owner:self
		userInfo:nil];
	[self addTrackingArea:_trackingArea];
}

- (void)mouseMoved:(NSEvent*)event
{
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	[self setHoveredRow:[self rowAtPoint:point]];
}

- (void)mouseExited:(NSEvent*)event
{
	[self setHoveredRow:-1];
}

- (void)setHoveredRow:(NSInteger)newRow
{
	if(_hoveredRow == newRow)
		return;
	NSInteger oldRow = _hoveredRow;
	_hoveredRow = newRow;
	if(oldRow >= 0 && oldRow < self.numberOfRows)
		[self setNeedsDisplayInRect:[self rectOfRow:oldRow]];
	if(newRow >= 0 && newRow < self.numberOfRows)
		[self setNeedsDisplayInRect:[self rectOfRow:newRow]];
}

- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect
{
	if(row == _hoveredRow && ![self.selectedRowIndexes containsIndex:row])
	{
		[[NSColor.secondaryLabelColor colorWithAlphaComponent:0.08] set];
		NSRectFillUsingOperation([self rectOfRow:row], NSCompositingOperationSourceOver);
	}
	[super drawRow:row clipRect:clipRect];
}

@end

@interface BundlesPreferences () <NSTableViewDelegate, NSMenuDelegate>
{
	NSMutableSet*              _enabledCategories;
	NSArrayController*         _arrayController;
	OakScopeBarViewController* _scopeBar;
	NSSearchField*             _searchField;
	OakHoverTableView*         _bundlesTableView;
}
@property (nonatomic) NSUInteger selectedIndex;
@end

@implementation BundlesPreferences
- (NSImage*)toolbarItemImage { return [NSWorkspace.sharedWorkspace iconForFileType:@"tmbundle"]; }

- (id)init
{
	if(self = [self initWithNibName:nil bundle:nil])
	{
		self.identifier = @"Bundles";
		self.title      = @"Bundles";

		_enabledCategories = [NSMutableSet set];
		_selectedIndex     = NSNotFound;

		_scopeBar = [[OakScopeBarViewController alloc] init];
		_scopeBar.allowsEmptySelection = YES;
		_scopeBar.controlSize = NSControlSizeSmall;
	}
	return self;
}

- (NSTableColumn*)columnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier title:(NSString*)title editable:(BOOL)editable width:(CGFloat)width resizingMask:(NSTableColumnResizingOptions)resizingMask
{
	NSTableColumn* tableColumn = [[NSTableColumn alloc] initWithIdentifier:identifier];

	tableColumn.title        = title;
	tableColumn.editable     = editable;
	tableColumn.width        = width;
	tableColumn.resizingMask = resizingMask;

	if(resizingMask == NSTableColumnNoResizing)
	{
		tableColumn.minWidth = width;
		tableColumn.maxWidth = width;
	}

	return tableColumn;
}

- (void)loadView
{
	NSMutableSet* categories = [NSMutableSet set];
	for(Bundle* bundle in BundlesManager.sharedInstance.bundles)
	{
		if(NSString* category = bundle.category)
			[categories addObject:category];
	}
	_scopeBar.labels = [[categories allObjects] sortedArrayUsingSelector:@selector(localizedCompare:)];

	_searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	_searchField.controlSize = NSControlSizeSmall;
	_searchField.font        = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
	_searchField.action      = @selector(filterStringDidChange:);
	[_searchField.cell setScrollable:YES];
	[_searchField.cell setSendsSearchStringImmediately:YES];

	_arrayController = [[NSArrayController alloc] init];
	_arrayController.avoidsEmptySelection = NO;
	_arrayController.sortDescriptors = @[
		[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCompare:)],
		[NSSortDescriptor sortDescriptorWithKey:@"installed" ascending:YES],
		[NSSortDescriptor sortDescriptorWithKey:@"downloadLastUpdated" ascending:YES],
		[NSSortDescriptor sortDescriptorWithKey:@"textSummary" ascending:YES selector:@selector(localizedCompare:)]
	];

	NSTableColumn* installedTableColumn   = [self columnWithIdentifier:kTableColumnIdentifierInstalled   title:@""            editable:YES width:16  resizingMask:NSTableColumnNoResizing];
	NSTableColumn* bundleTableColumn      = [self columnWithIdentifier:kTableColumnIdentifierBundleName  title:@"Bundle"      editable:NO  width:140 resizingMask:NSTableColumnUserResizingMask];
	NSTableColumn* linkTableColumn        = [self columnWithIdentifier:kTableColumnIdentifierWebLink     title:@""            editable:NO  width:16  resizingMask:NSTableColumnNoResizing];
	NSTableColumn* updatedTableColumn     = [self columnWithIdentifier:kTableColumnIdentifierUpdated     title:@"Updated"     editable:NO  width:90  resizingMask:NSTableColumnNoResizing];
	NSTableColumn* descriptionTableColumn = [self columnWithIdentifier:kTableColumnIdentifierDescription title:@"Description" editable:NO  width:140 resizingMask:NSTableColumnAutoresizingMask];
	NSTableColumn* actionsTableColumn     = [self columnWithIdentifier:kTableColumnIdentifierActions     title:@""            editable:NO  width:22  resizingMask:NSTableColumnNoResizing];

	NSButtonCell* installedCell = [[NSButtonCell alloc] init];
	installedCell.buttonType       = NSButtonTypeSwitch;
	installedCell.allowsMixedState = YES;
	installedCell.controlSize      = NSControlSizeSmall;
	installedCell.title            = @"";
	installedTableColumn.dataCell = installedCell;

	NSButtonCell* linkCell = [[NSButtonCell alloc] init];
	linkCell.buttonType  = NSButtonTypeMomentaryChange;
	linkCell.bezelStyle  = NSBezelStyleInline;
	linkCell.bordered    = NO;
	linkCell.controlSize = NSControlSizeSmall;
	linkCell.title       = @"";
	linkCell.action      = @selector(didClickBundleLink:);
	linkCell.target      = self;
	linkTableColumn.dataCell = linkCell;

	NSDateFormatter* updatedFormatter = [[NSDateFormatter alloc] init];
	updatedFormatter.dateStyle = NSDateFormatterMediumStyle;

	NSTextFieldCell* updatedCell = [[NSTextFieldCell alloc] initTextCell:@""];
	updatedCell.alignment = NSTextAlignmentRight;
	updatedCell.formatter = updatedFormatter;
	updatedTableColumn.dataCell = updatedCell;

	NSButtonCell* actionsCell = [[NSButtonCell alloc] init];
	actionsCell.buttonType  = NSButtonTypeMomentaryChange;
	actionsCell.bezelStyle  = NSBezelStyleInline;
	actionsCell.bordered    = NO;
	actionsCell.controlSize = NSControlSizeSmall;
	actionsCell.title       = @"";
	actionsCell.action      = @selector(didClickActionGear:);
	actionsCell.target      = self;
	actionsTableColumn.dataCell = actionsCell;

	_bundlesTableView = [[OakHoverTableView alloc] initWithFrame:NSZeroRect];
	_bundlesTableView.allowsColumnReordering  = NO;
	_bundlesTableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
	_bundlesTableView.delegate                = self;

	NSMenu* contextMenu = [[NSMenu alloc] initWithTitle:@""];
	contextMenu.delegate = self;
	_bundlesTableView.menu = contextMenu;

	for(NSTableColumn* tableColumn in @[ installedTableColumn, bundleTableColumn, linkTableColumn, updatedTableColumn, descriptionTableColumn, actionsTableColumn ])
		[_bundlesTableView addTableColumn:tableColumn];
	[_bundlesTableView setIndicatorImage:[NSImage imageNamed:@"NSAscendingSortIndicator"] inTableColumn:bundleTableColumn];

	NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scrollView.hasVerticalScroller   = YES;
	scrollView.hasHorizontalScroller = NO;
	scrollView.autohidesScrollers    = YES;
	scrollView.borderType            = NSBezelBorder;
	scrollView.documentView          = _bundlesTableView;

	NSButton* updateBundlesCheckbox = [NSButton checkboxWithTitle:@"Check for and install updates automatically" target:nil action:nil];

	NSButton* addBundleButton = [NSButton buttonWithTitle:@"+ Add Bundle…" target:self action:@selector(showAddBundleSheet:)];
	addBundleButton.controlSize = NSControlSizeSmall;
	addBundleButton.bezelStyle  = NSBezelStyleRounded;

	NSButton* checkNowButton = [NSButton buttonWithTitle:@"Check Now" target:self action:@selector(checkForUpdatesNow:)];
	checkNowButton.controlSize = NSControlSizeSmall;
	checkNowButton.bezelStyle  = NSBezelStyleRounded;

	NSTextField* statusTextField = [NSTextField labelWithString:@""];
	statusTextField.textColor = NSColor.secondaryLabelColor;
	statusTextField.font = [NSFont messageFontOfSize:NSFont.smallSystemFontSize];

	NSProgressIndicator* progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progressIndicator.controlSize          = NSControlSizeSmall;
	progressIndicator.displayedWhenStopped = NO;
	progressIndicator.style                = NSProgressIndicatorStyleSpinning;

	NSVisualEffectView* footerView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	footerView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
	footerView.material     = NSVisualEffectMaterialTitlebar;

	NSDictionary* footerViews = @{
		@"divider": OakCreateNSBoxSeparator(),
		@"spinner": progressIndicator,
		@"status":  statusTextField,
	};
	OakAddAutoLayoutViewsToSuperview(footerViews.allValues, footerView);
	[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[divider]|"                        options:0 metrics:nil views:footerViews]];
	[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[spinner]-(>=8)-[status]-(>=8)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:footerViews]];
	[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[divider(==1)]-4-[status]-4-|"     options:0 metrics:nil views:footerViews]];
	[statusTextField.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor].active = YES;

	NSDictionary* views = @{
		@"scopeBar":      _scopeBar.view,
		@"search":        _searchField,
		@"scrollView":    scrollView,
		@"addBundle":     addBundleButton,
		@"checkNow":      checkNowButton,
		@"updateBundles": updateBundlesCheckbox,
		@"footer":        footerView,
	};

	NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 622, 454)];
	OakAddAutoLayoutViewsToSuperview(views.allValues, view);

	[view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-8-[scopeBar]-(>=8)-[search(>=50,<=100,==100@250)]-8-|"        options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[scrollView(>=50)]-|"                                         options:0 metrics:nil views:views]];
	[view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[addBundle]-8-[checkNow]-(>=8)-[updateBundles]-|"             options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[footer]|"                                                     options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-8-[search]-8-[scrollView(>=50)]-[addBundle]-20-[footer]|"     options:0 metrics:nil views:views]];

	// ============
	// = Bindings =
	// ============

	[_arrayController bind:NSContentBinding toObject:BundlesManager.sharedInstance withKeyPath:@"bundles" options:nil];
	[_scopeBar bind:NSValueBinding toObject:self withKeyPath:@"selectedIndex" options:nil];

	[_bundlesTableView bind:NSContentBinding          toObject:_arrayController withKeyPath:@"arrangedObjects" options:nil];
	[_bundlesTableView bind:NSSelectionIndexesBinding toObject:_arrayController withKeyPath:@"selectionIndexes" options:nil];

	[installedTableColumn   bind:NSValueBinding toObject:_arrayController withKeyPath:@"arrangedObjects.installedCellState" options:nil];
	[bundleTableColumn      bind:NSValueBinding toObject:_arrayController withKeyPath:@"arrangedObjects.name" options:nil];
	[updatedTableColumn     bind:NSValueBinding toObject:_arrayController withKeyPath:@"arrangedObjects.downloadLastUpdated" options:nil];
	[descriptionTableColumn bind:NSValueBinding toObject:_arrayController withKeyPath:@"arrangedObjects.textSummary" options:nil];

	[updateBundlesCheckbox bind:NSValueBinding toObject:NSUserDefaultsController.sharedUserDefaultsController withKeyPath:@"values.disableBundleUpdates" options:@{ NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName }];

	[progressIndicator bind:NSAnimateBinding toObject:BundleInstallHelper.sharedInstance withKeyPath:@"busy" options:nil];
	[statusTextField   bind:NSValueBinding   toObject:BundleInstallHelper.sharedInstance withKeyPath:@"activityText" options:nil];

	self.view = view;
}

- (void)viewWillAppear
{
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = nil;
}

- (void)viewDidAppear
{
	NSResponder* firstResponder = self.view.window.firstResponder;
	if(!firstResponder || firstResponder == self.view.window || ([firstResponder isKindOfClass:[NSView class]] && [(NSView*)firstResponder isDescendantOf:self.view]))
		[self.view.window makeFirstResponder:_bundlesTableView];
}

- (void)setSelectedIndex:(NSUInteger)newSelectedIndex
{
	_selectedIndex = newSelectedIndex;
	[_enabledCategories removeAllObjects];
	if(_selectedIndex < _scopeBar.labels.count)
		[_enabledCategories addObject:_scopeBar.labels[_selectedIndex]];
	[self filterStringDidChange:self];
}

- (void)filterStringDidChange:(id)sender
{
	NSMutableArray* predicates = [NSMutableArray array];
	if(OakNotEmptyString(_searchField.stringValue))
		[predicates addObject:[NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", _searchField.stringValue]];
	if(_enabledCategories.count)
		[predicates addObject:[NSPredicate predicateWithFormat:@"category IN %@", _enabledCategories]];
	_arrayController.filterPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
	[_arrayController rearrangeObjects];
}

// ========================
// = NSTableView Delegate =
// ========================

- (void)tableView:(NSTableView*)aTableView didClickTableColumn:(NSTableColumn*)aTableColumn
{
	NSDictionary* map = @{
		kTableColumnIdentifierInstalled:   @"installed",
		kTableColumnIdentifierBundleName:  @"name",
		kTableColumnIdentifierUpdated:     @"downloadLastUpdated",
		kTableColumnIdentifierDescription: @"textSummary"
	};

	NSString* key = map[aTableColumn.identifier];
	if(!key)
		return;

	NSMutableArray* descriptors = [_arrayController.sortDescriptors mutableCopy];

	NSInteger i = 0;
	while(i < descriptors.count && ![_arrayController.sortDescriptors[i].key isEqualToString:key])
		++i;

	if(i == descriptors.count)
		return;

	NSSortDescriptor* descriptor = descriptors[i];
	descriptor = i == 0 || !descriptor.ascending ? [descriptor reversedSortDescriptor] : descriptor;
	[descriptors removeObjectAtIndex:i];
	[descriptors insertObject:descriptor atIndex:0];

	_arrayController.sortDescriptors = descriptors;

	for(NSTableColumn* tableColumn in [_bundlesTableView tableColumns])
		[aTableView setIndicatorImage:nil inTableColumn:tableColumn];
	[aTableView setIndicatorImage:[NSImage imageNamed:(descriptor.ascending ? @"NSAscendingSortIndicator" : @"NSDescendingSortIndicator")] inTableColumn:aTableColumn];
}

- (void)tableView:(NSTableView*)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	if([aTableColumn.identifier isEqualToString:kTableColumnIdentifierWebLink])
	{
		Bundle* bundle = _arrayController.arrangedObjects[rowIndex];
		BOOL enabled = bundle.htmlURL ? YES : NO;
		[aCell setEnabled:enabled];
		[aCell setImage:enabled ? [NSImage imageNamed:@"NSFollowLinkFreestandingTemplate"] : nil];
	}
	else if([aTableColumn.identifier isEqualToString:kTableColumnIdentifierInstalled])
	{
		Bundle* bundle = _arrayController.arrangedObjects[rowIndex];
		[aCell setEnabled:!bundle.isMandatory || !bundle.isInstalled];
	}
	else if([aTableColumn.identifier isEqualToString:kTableColumnIdentifierActions])
	{
		NSImage* gear = nil;
		if(@available(macos 11.0, *))
			gear = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Bundle options"];
		[aCell setImage:gear];
		[aCell setEnabled:YES];
	}
}

- (BOOL)tableView:(NSTableView*)aTableView shouldEditTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	if([aTableColumn.identifier isEqualToString:kTableColumnIdentifierInstalled])
	{
		Bundle* bundle = _arrayController.arrangedObjects[rowIndex];
		return bundle.installedCellState != NSControlStateValueMixed;
	}
	return NO;
}

- (BOOL)tableView:(NSTableView*)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	NSInteger clickedColumn = aTableView.clickedColumn;
	if(clickedColumn == [aTableView columnWithIdentifier:kTableColumnIdentifierInstalled])   return NO;
	if(clickedColumn == [aTableView columnWithIdentifier:kTableColumnIdentifierWebLink])     return NO;
	if(clickedColumn == [aTableView columnWithIdentifier:kTableColumnIdentifierActions])     return NO;
	return YES;
}

- (void)didClickBundleLink:(NSTableView*)aTableView
{
	NSInteger rowIndex = aTableView.clickedRow;
	Bundle* bundle = _arrayController.arrangedObjects[rowIndex];
	if(bundle.htmlURL)
		[NSWorkspace.sharedWorkspace openURL:bundle.htmlURL];
}

// ================
// = Add Bundle UI
// ================

- (void)showAddBundleSheet:(id)sender
{
	NSAlert* alert = [[NSAlert alloc] init];
	alert.messageText     = @"Add Bundle from URL";
	alert.informativeText = @"Enter the GitHub URL for a TextMate bundle and the branch, tag, or commit to track. The bundle will be fetched and installed immediately.";
	[alert addButtonWithTitle:@"Add"];
	[alert addButtonWithTitle:@"Cancel"];

	NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 60)];

	NSTextField* urlLabel = [NSTextField labelWithString:@"URL:"];
	NSTextField* urlField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	urlField.placeholderString = @"https://github.com/owner/repo.tmbundle";
	[urlField.cell setWraps:NO];
	[urlField.cell setScrollable:YES];

	NSTextField* refLabel = [NSTextField labelWithString:@"Ref:"];
	NSTextField* refField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	refField.placeholderString = @"main";

	NSDictionary* views = @{ @"urlLabel": urlLabel, @"url": urlField, @"refLabel": refLabel, @"ref": refField };
	for(NSView* v in views.allValues) { v.translatesAutoresizingMaskIntoConstraints = NO; [accessory addSubview:v]; }
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[urlLabel(==40)]-[url(>=260)]|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[refLabel(==40)]-[ref(>=260)]|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[url]-8-[ref]|"                 options:0 metrics:nil views:views]];

	alert.accessoryView = accessory;

	NSWindow* parent = self.view.window;
	[alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response){
		if(response != NSAlertFirstButtonReturn)
			return;

		NSString* url = [urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString* ref = [refField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if(url.length == 0)
			return;

		BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching %@…", url];

		[BundlesManager.sharedInstance addBundleFromURL:url ref:ref name:nil completion:^(NSString* sha, NSError* error){
			if(error)
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Add failed: %@", error.localizedDescription];
				NSAlert* errAlert = [NSAlert alertWithError:error];
				[errAlert beginSheetModalForWindow:parent completionHandler:nil];
			}
			else
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Added bundle @ %@", sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
			}
		}];
	}];
}

- (void)checkForUpdatesNow:(id)sender
{
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = @"Checking for bundle updates…";
	[BundlesManager.sharedInstance checkForBundleUpdatesNowWithCompletion:^{
		BundleInstallHelper.sharedInstance.bundleInstallActivityText = @"Bundle check complete.";
	}];
}

// ================
// = Menu (gear + right-click) shared builder
// ================

- (void)populateMenu:(NSMenu*)menu forBundle:(Bundle*)bundle
{
	[menu removeAllItems];
	if(!bundle)
		return;

	BOOL mandatory = bundle.isMandatory;
	BOOL isEditedShipped = [BundlesManager.sharedInstance bundleIsEditedShippedDefault:bundle];

	NSMenuItem* autoItem = [menu addItemWithTitle:@"Auto Update" action:@selector(toggleAutoUpdate:) keyEquivalent:@""];
	autoItem.target = self;
	autoItem.representedObject = bundle;
	autoItem.state = bundle.autoUpdateEnabled ? NSControlStateValueOn : NSControlStateValueOff;
	autoItem.enabled = !mandatory;

	[menu addItem:NSMenuItem.separatorItem];

	NSMenuItem* changeRefItem = [menu addItemWithTitle:@"Change Ref…" action:@selector(showChangeRefSheet:) keyEquivalent:@""];
	changeRefItem.target = self;
	changeRefItem.representedObject = bundle;
	changeRefItem.enabled = !mandatory;

	NSMenuItem* editItem = [menu addItemWithTitle:@"Edit Bundle…" action:@selector(showEditBundleSheet:) keyEquivalent:@""];
	editItem.target = self;
	editItem.representedObject = bundle;
	editItem.enabled = !mandatory;

	[menu addItem:NSMenuItem.separatorItem];

	NSMenuItem* uninstallItem = [menu addItemWithTitle:@"Uninstall" action:@selector(uninstallFromMenu:) keyEquivalent:@""];
	uninstallItem.target = self;
	uninstallItem.representedObject = bundle;
	uninstallItem.enabled = !mandatory && bundle.isInstalled;

	NSMenuItem* removeItem = [menu addItemWithTitle:@"Remove Bundle…" action:@selector(removeFromMenu:) keyEquivalent:@""];
	removeItem.target = self;
	removeItem.representedObject = bundle;
	removeItem.enabled = !mandatory;

	NSMenuItem* revertItem = [menu addItemWithTitle:@"Revert to Default" action:@selector(revertFromMenu:) keyEquivalent:@""];
	revertItem.target = self;
	revertItem.representedObject = bundle;
	revertItem.enabled = isEditedShipped;

	[menu addItem:NSMenuItem.separatorItem];

	NSMenuItem* copyItem = [menu addItemWithTitle:@"Copy URL" action:@selector(copyBundleURL:) keyEquivalent:@""];
	copyItem.target = self;
	copyItem.representedObject = bundle;
	copyItem.enabled = bundle.downloadURL != nil;

	NSMenuItem* revealItem = [menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealBundleInFinder:) keyEquivalent:@""];
	revealItem.target = self;
	revealItem.representedObject = bundle;
	revealItem.enabled = bundle.path != nil;
}

- (void)menuNeedsUpdate:(NSMenu*)menu
{
	NSInteger row = _bundlesTableView.clickedRow;
	Bundle* bundle = (row >= 0 && row < (NSInteger)[_arrayController.arrangedObjects count]) ? _arrayController.arrangedObjects[row] : nil;
	[self populateMenu:menu forBundle:bundle];
}

- (void)didClickActionGear:(NSTableView*)aTableView
{
	NSInteger row = aTableView.clickedRow;
	if(row < 0 || row >= (NSInteger)[_arrayController.arrangedObjects count])
		return;

	Bundle* bundle = _arrayController.arrangedObjects[row];
	NSMenu* menu = [[NSMenu alloc] init];
	[self populateMenu:menu forBundle:bundle];

	NSInteger col = [aTableView columnWithIdentifier:kTableColumnIdentifierActions];
	NSRect rect = [aTableView frameOfCellAtColumn:col row:row];
	NSPoint location = NSMakePoint(NSMinX(rect), NSMaxY(rect));
	[menu popUpMenuPositioningItem:nil atLocation:location inView:aTableView];
}

// ================
// = Menu actions
// ================

- (void)toggleAutoUpdate:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle || bundle.isMandatory)
		return;
	BOOL newValue = !bundle.autoUpdateEnabled;
	[BundlesManager.sharedInstance setAutoUpdate:newValue forBundle:bundle];
	bundle.autoUpdateEnabled = newValue;
}

- (void)showChangeRefSheet:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle || bundle.isMandatory)
		return;

	NSAlert* alert = [[NSAlert alloc] init];
	alert.messageText     = [NSString stringWithFormat:@"Change Ref for “%@”", bundle.name];
	alert.informativeText = @"Enter a branch, tag, or 40-character commit SHA. The bundle will be re-fetched at the new ref.";
	[alert addButtonWithTitle:@"Update"];
	[alert addButtonWithTitle:@"Cancel"];

	NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
	field.placeholderString = @"main";
	field.stringValue       = bundle.ref ?: @"";
	alert.accessoryView = field;

	NSWindow* parent = self.view.window;
	[alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response){
		if(response != NSAlertFirstButtonReturn)
			return;

		NSString* ref = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if(ref.length == 0)
			return;

		BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching “%@” @ %@…", bundle.name, ref];
		[BundlesManager.sharedInstance updateBundle:bundle url:nil ref:ref completion:^(NSString* sha, NSError* error){
			if(error)
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Change failed: %@", error.localizedDescription];
				NSAlert* errAlert = [NSAlert alertWithError:error];
				[errAlert beginSheetModalForWindow:parent completionHandler:nil];
			}
			else
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Updated “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
			}
		}];
	}];
}

- (void)showEditBundleSheet:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle || bundle.isMandatory)
		return;

	NSAlert* alert = [[NSAlert alloc] init];
	alert.messageText     = [NSString stringWithFormat:@"Edit Bundle “%@”", bundle.name];
	alert.informativeText = @"Change the URL or ref. Changing the URL re-fetches the bundle; the UUID in the fetched info.plist must match. Name is derived from info.plist and cannot be edited here.";
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Cancel"];

	NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 60)];
	NSTextField* urlLabel = [NSTextField labelWithString:@"URL:"];
	NSTextField* urlField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	urlField.stringValue = bundle.downloadURL.absoluteString ?: @"";
	[urlField.cell setWraps:NO];
	[urlField.cell setScrollable:YES];
	NSTextField* refLabel = [NSTextField labelWithString:@"Ref:"];
	NSTextField* refField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	refField.stringValue = bundle.ref ?: @"";

	NSDictionary* views = @{ @"urlLabel": urlLabel, @"url": urlField, @"refLabel": refLabel, @"ref": refField };
	for(NSView* v in views.allValues) { v.translatesAutoresizingMaskIntoConstraints = NO; [accessory addSubview:v]; }
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[urlLabel(==40)]-[url(>=260)]|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[refLabel(==40)]-[ref(>=260)]|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
	[accessory addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[url]-8-[ref]|"                 options:0 metrics:nil views:views]];
	alert.accessoryView = accessory;

	NSWindow* parent = self.view.window;
	[alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response){
		if(response != NSAlertFirstButtonReturn)
			return;
		NSString* url = [urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString* ref = [refField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if(url.length == 0)
			return;

		BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching “%@”…", bundle.name];
		[BundlesManager.sharedInstance updateBundle:bundle url:url ref:(ref.length ? ref : nil) completion:^(NSString* sha, NSError* error){
			if(error)
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Edit failed: %@", error.localizedDescription];
				NSAlert* errAlert = [NSAlert alertWithError:error];
				[errAlert beginSheetModalForWindow:parent completionHandler:nil];
			}
			else
			{
				BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Updated “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
			}
		}];
	}];
}

- (void)uninstallFromMenu:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle || bundle.isMandatory)
		return;
	[BundleInstallHelper.sharedInstance uninstallBundle:bundle];
}

- (void)removeFromMenu:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle || bundle.isMandatory)
		return;

	NSAlert* alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:@"Remove bundle “%@”?", bundle.name];
	alert.informativeText = @"The bundle will be uninstalled and removed from the registry. You can re-add it later from the URL.";
	[alert addButtonWithTitle:@"Remove"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){
		if(response != NSAlertFirstButtonReturn)
			return;
		[BundlesManager.sharedInstance removeBundleSpec:bundle];
		BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Removed bundle “%@”.", bundle.name];
	}];
}

- (void)revertFromMenu:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle)
		return;

	NSWindow* parent = self.view.window;
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Reverting “%@”…", bundle.name];
	[BundlesManager.sharedInstance revertBundleToDefault:bundle completion:^(NSString* sha, NSError* error){
		if(error)
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Revert failed: %@", error.localizedDescription];
			NSAlert* errAlert = [NSAlert alertWithError:error];
			[errAlert beginSheetModalForWindow:parent completionHandler:nil];
		}
		else
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Reverted “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
		}
	}];
}

- (void)copyBundleURL:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(!bundle.downloadURL)
		return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard writeObjects:@[ bundle.downloadURL.absoluteString ]];
}

- (void)revealBundleInFinder:(NSMenuItem*)item
{
	Bundle* bundle = item.representedObject;
	if(bundle.path)
		[NSWorkspace.sharedWorkspace selectFile:bundle.path inFileViewerRootedAtPath:@""];
}

@end
