#import <HTMLOutput/HTMLOutput.h>
#import <OakTabBarView/OakTabBarView.h>

@class OakHTMLOutputTabView;

@protocol OakHTMLOutputTabViewDelegate <NSObject>
@optional
- (void)htmlOutputTabViewDidRemoveLastView:(OakHTMLOutputTabView*)tabView;
@end

// Several HTML output views behind one tab strip. Only the selected view is
// shown; every view keeps its own page, history, environment and command.
@interface OakHTMLOutputTabView : NSView
@property (nonatomic, weak) id <OakHTMLOutputTabViewDelegate> delegate;
@property (nonatomic, readonly) OakTabBarView* tabBarView;
@property (nonatomic) BOOL hostsTabBar; // NO when the owner places the tab bar itself, e.g. in the title bar

@property (nonatomic, readonly) NSArray<OakHTMLOutputView*>* htmlOutputViews;
@property (nonatomic) OakHTMLOutputView* selectedHTMLOutputView;

- (void)addHTMLOutputView:(OakHTMLOutputView*)aView; // appends and selects
- (void)removeHTMLOutputView:(OakHTMLOutputView*)aView;

// Selects the tab holding the view. Reachable from the view through the responder chain.
- (void)revealHTMLOutputView:(OakHTMLOutputView*)aView;
@end
