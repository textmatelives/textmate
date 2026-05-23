#import "FirstLaunchBundleInstaller.h"
#import <BundlesManager/BundlesManager.h>
#import <BundlesManager/BundleRegistry.h>
#import <BundlesManager/BundleSpec.h>

static NSString* const kColumnCheck    = @"check";
static NSString* const kColumnName     = @"name";
static NSString* const kColumnCategory = @"category";
static NSString* const kColumnSummary  = @"summary";

// NSTableView subclass that toggles the selected row's checkbox on Space.
// Falls back to the default keyDown behaviour for any other key.
@interface FLBITableView : NSTableView
@end

@implementation FLBITableView
- (void)keyDown:(NSEvent*)event
{
	if([event.charactersIgnoringModifiers isEqualToString:@" "] && self.selectedRow != -1)
	{
		NSTableCellView* cell = [self viewAtColumn:0 row:self.selectedRow makeIfNecessary:NO];
		NSButton* cb = (NSButton*)cell.subviews.firstObject;
		if([cb isKindOfClass:NSButton.class])
		{
			cb.state = (cb.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
			[cb sendAction:cb.action to:cb.target];
			return;
		}
	}
	[super keyDown:event];
}
@end

@interface FirstLaunchBundleInstaller () <NSTableViewDataSource, NSTableViewDelegate>
{
	NSMutableSet<NSUUID*>*       _selected;
	NSArray<BundleSpec*>*        _candidates;
	NSTableView*                 _tableView;
	NSTextField*                 _statusLabel;
	NSProgressIndicator*         _progress;
	NSButton*                    _skipButton;
	NSButton*                    _installButton;
	NSProgress*                  _installProgress;
}
@end

@implementation FirstLaunchBundleInstaller

+ (NSArray<BundleSpec*>*)candidateSpecs
{
	NSArray* never = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey] ?: @[];
	NSMutableSet<NSString*>* skipUUIDs = [NSMutableSet setWithCapacity:never.count];
	for(NSString* s in never)
		[skipUUIDs addObject:s.uppercaseString];

	NSMutableArray<BundleSpec*>* res = [NSMutableArray array];
	for(BundleSpec* spec in BundleRegistry.sharedInstance.allSpecs)
	{
		if(spec.origin != TMBundleOriginShipped)
			continue;
		if(spec.installedSHA)
			continue;
		if([skipUUIDs containsObject:spec.uuid.UUIDString.uppercaseString])
			continue;
		[res addObject:spec];
	}
	[res sortUsingComparator:^NSComparisonResult(BundleSpec* a, BundleSpec* b){
		NSComparisonResult c = [(a.category ?: @"Other") localizedCaseInsensitiveCompare:b.category ?: @"Other"];
		return c != NSOrderedSame ? c : [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return res;
}

static FirstLaunchBundleInstaller* sActiveInstaller;

+ (void)promptIfNeeded
{
	NSUserDefaults* def = NSUserDefaults.standardUserDefaults;
	if([def boolForKey:kUserDefaultsDidPromptForDefaultBundlesKey])
		return;

	NSArray<BundleSpec*>* candidates = [self candidateSpecs];
	if(candidates.count == 0)
	{
		[def setBool:YES forKey:kUserDefaultsDidPromptForDefaultBundlesKey];
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		sActiveInstaller = [[FirstLaunchBundleInstaller alloc] initWithCandidates:candidates];
		(void)sActiveInstaller.window; // force load
		[sActiveInstaller show];
	});
}

- (instancetype)initWithCandidates:(NSArray<BundleSpec*>*)candidates
{
	NSWindow* win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 520)
	                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
	                                              backing:NSBackingStoreBuffered
	                                                defer:NO];
	win.title = @"Install Default Bundles";
	win.minSize = NSMakeSize(560, 360);
	win.preventsApplicationTerminationWhenModal = NO;

	if(self = [super initWithWindow:win])
	{
		_candidates = candidates;
		_selected   = [NSMutableSet setWithCapacity:candidates.count];
		for(BundleSpec* s in candidates)
			[_selected addObject:s.uuid];
		[self buildContentView];
	}
	return self;
}

- (void)buildContentView
{
	NSView* root = [[NSView alloc] initWithFrame:NSZeroRect];
	root.translatesAutoresizingMaskIntoConstraints = NO;
	self.window.contentView = root;

	NSTextField* title = [NSTextField labelWithString:@"TextMate ships a curated set of bundles for common languages and tools."];
	title.font = [NSFont boldSystemFontOfSize:13];

	NSTextField* subtitle = [NSTextField wrappingLabelWithString:@"Pick which to install now. Unchecked bundles will not be suggested again — you can always install them later from Preferences › Bundles."];
	subtitle.font = [NSFont systemFontOfSize:11];
	subtitle.textColor = NSColor.secondaryLabelColor;
	subtitle.maximumNumberOfLines = 0;

	NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.borderType = NSBezelBorder;
	scroll.hasVerticalScroller = YES;
	scroll.autohidesScrollers = YES;

	_tableView = [[FLBITableView alloc] initWithFrame:NSZeroRect];
	_tableView.dataSource          = self;
	_tableView.delegate            = self;
	_tableView.headerView          = nil;
	_tableView.usesAlternatingRowBackgroundColors = YES;
	_tableView.rowSizeStyle        = NSTableViewRowSizeStyleMedium;
	_tableView.allowsColumnReordering  = NO;
	_tableView.allowsColumnResizing    = NO;
	_tableView.allowsMultipleSelection = NO;
	_tableView.allowsEmptySelection    = YES;
	_tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

	NSTableColumn* col0 = [[NSTableColumn alloc] initWithIdentifier:kColumnCheck];
	col0.width = 22; col0.minWidth = 22; col0.maxWidth = 22;
	[_tableView addTableColumn:col0];

	NSTableColumn* col1 = [[NSTableColumn alloc] initWithIdentifier:kColumnName];
	col1.width = 160; col1.minWidth = 120;
	[_tableView addTableColumn:col1];

	NSTableColumn* col2 = [[NSTableColumn alloc] initWithIdentifier:kColumnCategory];
	col2.width = 110; col2.minWidth = 80; col2.maxWidth = 160;
	[_tableView addTableColumn:col2];

	NSTableColumn* col3 = [[NSTableColumn alloc] initWithIdentifier:kColumnSummary];
	col3.width = 360; col3.minWidth = 200;
	[_tableView addTableColumn:col3];

	scroll.documentView = _tableView;

	_statusLabel = [NSTextField labelWithString:@""];
	_statusLabel.font = [NSFont systemFontOfSize:11];
	_statusLabel.textColor = NSColor.secondaryLabelColor;

	_progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	_progress.style = NSProgressIndicatorStyleBar;
	_progress.indeterminate = NO;
	_progress.minValue = 0;
	_progress.maxValue = 1;
	_progress.doubleValue = 0;
	_progress.displayedWhenStopped = NO;
	_progress.controlSize = NSControlSizeSmall;

	_skipButton = [NSButton buttonWithTitle:@"Skip" target:self action:@selector(skip:)];
	_skipButton.keyEquivalent = @"\e";

	_installButton = [NSButton buttonWithTitle:@"Install Selected" target:self action:@selector(installSelected:)];
	_installButton.keyEquivalent = @"\r";

	NSDictionary* views = NSDictionaryOfVariableBindings(title, subtitle, scroll, _statusLabel, _progress, _skipButton, _installButton);
	for(NSView* v in views.allValues)
		v.translatesAutoresizingMaskIntoConstraints = NO;
	for(NSView* v in views.allValues)
		[root addSubview:v];

	[NSLayoutConstraint activateConstraints:@[
		[title.topAnchor      constraintEqualToAnchor:root.topAnchor      constant:20],
		[title.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor  constant:20],
		[title.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

		[subtitle.topAnchor      constraintEqualToAnchor:title.bottomAnchor constant:6],
		[subtitle.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor  constant:20],
		[subtitle.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

		[scroll.topAnchor      constraintEqualToAnchor:subtitle.bottomAnchor constant:12],
		[scroll.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor    constant:20],
		[scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor   constant:-20],

		[_progress.leadingAnchor   constraintEqualToAnchor:root.leadingAnchor constant:20],
		[_progress.centerYAnchor   constraintEqualToAnchor:_installButton.centerYAnchor],
		[_progress.widthAnchor     constraintEqualToConstant:120],

		[_statusLabel.leadingAnchor  constraintEqualToAnchor:_progress.trailingAnchor constant:8],
		[_statusLabel.centerYAnchor  constraintEqualToAnchor:_installButton.centerYAnchor],
		[_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_skipButton.leadingAnchor constant:-12],

		[_installButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
		[_installButton.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor   constant:-20],

		[_skipButton.trailingAnchor constraintEqualToAnchor:_installButton.leadingAnchor constant:-12],
		[_skipButton.centerYAnchor  constraintEqualToAnchor:_installButton.centerYAnchor],

		[scroll.bottomAnchor constraintEqualToAnchor:_installButton.topAnchor constant:-16],
	]];
}

- (void)show
{
	self.window.level = NSFloatingWindowLevel;
	[self.window center];
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)dismiss
{
	[self.window orderOut:nil];
	if(sActiveInstaller == self)
		sActiveInstaller = nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv
{
	return _candidates.count;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)col row:(NSInteger)row
{
	BundleSpec* spec = _candidates[row];
	NSString* ident = col.identifier;
	NSTableCellView* cell = [tv makeViewWithIdentifier:ident owner:self];
	if(!cell)
	{
		cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell.identifier = ident;
		if([ident isEqualToString:kColumnCheck])
		{
			NSButton* cb = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleRow:)];
			cb.translatesAutoresizingMaskIntoConstraints = NO;
			cb.tag = row;
			[cell addSubview:cb];
			[NSLayoutConstraint activateConstraints:@[
				[cb.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
				[cb.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
			]];
		}
		else
		{
			NSTextField* tf = [NSTextField labelWithString:@""];
			tf.translatesAutoresizingMaskIntoConstraints = NO;
			tf.lineBreakMode = NSLineBreakByTruncatingTail;
			tf.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
			[cell addSubview:tf];
			cell.textField = tf;
			[NSLayoutConstraint activateConstraints:@[
				[tf.leadingAnchor  constraintEqualToAnchor:cell.leadingAnchor  constant:2],
				[tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
				[tf.centerYAnchor  constraintEqualToAnchor:cell.centerYAnchor],
			]];
		}
	}

	if([ident isEqualToString:kColumnCheck])
	{
		NSButton* cb = (NSButton*)cell.subviews.firstObject;
		cb.tag = row;
		cb.state = [_selected containsObject:spec.uuid] ? NSControlStateValueOn : NSControlStateValueOff;
	}
	else if([ident isEqualToString:kColumnName])
	{
		cell.textField.stringValue = spec.name ?: @"";
		cell.textField.textColor = NSColor.labelColor;
	}
	else if([ident isEqualToString:kColumnCategory])
	{
		cell.textField.stringValue = spec.category ?: @"Other";
		cell.textField.textColor = NSColor.secondaryLabelColor;
	}
	else if([ident isEqualToString:kColumnSummary])
	{
		cell.textField.stringValue = spec.summary ?: @"";
		cell.textField.textColor = NSColor.secondaryLabelColor;
	}

	return cell;
}

- (void)toggleRow:(NSButton*)sender
{
	NSInteger row = sender.tag;
	if(row < 0 || (NSUInteger)row >= _candidates.count)
		return;
	BundleSpec* spec = _candidates[row];
	if(sender.state == NSControlStateValueOn)
		[_selected addObject:spec.uuid];
	else
		[_selected removeObject:spec.uuid];
}

- (void)skip:(id)sender
{
	// Mark every candidate as never-suggest so the on-demand per-extension
	// prompt won't ambush the user later on.
	NSArray* never = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey] ?: @[];
	NSMutableSet* set = [NSMutableSet setWithArray:never];
	for(BundleSpec* spec in _candidates)
		[set addObject:spec.uuid.UUIDString];
	[NSUserDefaults.standardUserDefaults setObject:set.allObjects forKey:kUserDefaultsBundlesToNeverSuggestKey];

	[NSUserDefaults.standardUserDefaults setBool:YES forKey:kUserDefaultsDidPromptForDefaultBundlesKey];

	[self dismiss];
}

- (void)installSelected:(id)sender
{
	NSMutableArray<BundleSpec*>* toInstall   = [NSMutableArray array];
	NSMutableArray<NSString*>*   toNeverHint = [NSMutableArray array];
	for(BundleSpec* spec in _candidates)
	{
		if([_selected containsObject:spec.uuid])
			[toInstall addObject:spec];
		else
			[toNeverHint addObject:spec.uuid.UUIDString];
	}

	if(toNeverHint.count > 0)
	{
		NSArray* never = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey] ?: @[];
		NSMutableSet* set = [NSMutableSet setWithArray:never];
		[set addObjectsFromArray:toNeverHint];
		[NSUserDefaults.standardUserDefaults setObject:set.allObjects forKey:kUserDefaultsBundlesToNeverSuggestKey];
	}

	if(toInstall.count == 0)
	{
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:kUserDefaultsDidPromptForDefaultBundlesKey];
		[self dismiss];
		return;
	}

	_skipButton.enabled    = NO;
	_installButton.enabled = NO;
	_tableView.enabled     = NO;
	_statusLabel.stringValue = [NSString stringWithFormat:@"Installed 0 of %lu…", (unsigned long)toInstall.count];
	_progress.doubleValue = 0;
	[_progress startAnimation:nil];

	_installProgress = [BundlesManager.sharedInstance installSpecs:toInstall completionHandler:^(NSArray<BundleSpec*>* installed){
		[self->_installProgress removeObserver:self forKeyPath:@"completedUnitCount"];
		self->_installProgress = nil;
		[self->_progress stopAnimation:nil];
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:kUserDefaultsDidPromptForDefaultBundlesKey];
		[self dismiss];
	}];
	[_installProgress addObserver:self forKeyPath:@"completedUnitCount" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(object != _installProgress)
		return;
	NSProgress* prog = _installProgress;
	int64_t done  = prog.completedUnitCount;
	int64_t total = prog.totalUnitCount;
	double frac   = prog.fractionCompleted;
	dispatch_async(dispatch_get_main_queue(), ^{
		self->_progress.doubleValue = frac;
		self->_statusLabel.stringValue = [NSString stringWithFormat:@"Installed %lld of %lld…", done, total];
	});
}

@end
