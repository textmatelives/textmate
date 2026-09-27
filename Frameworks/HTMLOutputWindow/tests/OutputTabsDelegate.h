#import <HTMLOutputWindow/OakHTMLOutputTabView.h>

// Counts the tab view's delegate calls, for the output tab tests.
@interface OutputTabsDelegate : NSObject <OakHTMLOutputTabViewDelegate>
@property (nonatomic) NSUInteger removedLastViewCount;
@property (nonatomic) NSUInteger lostWindowCount; // times an observed view reported it left its window
@property (nonatomic) NSMutableArray<OakHTMLOutputView*>* watched;
- (void)watchView:(OakHTMLOutputView*)view;
@end

@implementation OutputTabsDelegate
- (void)htmlOutputTabViewDidRemoveLastView:(OakHTMLOutputTabView*)tabView { ++_removedLastViewCount; }
- (void)watchView:(OakHTMLOutputView*)view
{
	(_watched = _watched ?: [NSMutableArray array]);
	[_watched addObject:view];
	[view addObserver:self forKeyPath:@"visible" options:NSKeyValueObservingOptionNew context:nullptr];
}

- (void)dealloc
{
	for(OakHTMLOutputView* view in _watched)
		[view removeObserver:self forKeyPath:@"visible"];
}
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(![change[NSKeyValueChangeNewKey] boolValue])
		++_lostWindowCount;
}
@end
