#import <HTMLOutputWindow/OakHTMLOutputTabView.h>

// Counts the tab view's delegate calls, for the output tab tests.
@interface OutputTabsDelegate : NSObject <OakHTMLOutputTabViewDelegate>
@property (nonatomic) NSUInteger removedLastViewCount;
@end

@implementation OutputTabsDelegate
- (void)htmlOutputTabViewDidRemoveLastView:(OakHTMLOutputTabView*)tabView { ++_removedLastViewCount; }
@end
