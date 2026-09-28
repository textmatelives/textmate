#import <HTMLOutput/HTMLOutput.h>
#import <OakTabBarView/OakTabBarView.h>

@class OakHTMLOutputTabView;
@class HTMLOutputWindowController;

@protocol OakHTMLOutputTabViewDelegate <NSObject>
@optional
- (void)htmlOutputTabViewDidRemoveLastView:(OakHTMLOutputTabView*)tabView;
- (void)htmlOutputTabView:(OakHTMLOutputTabView*)tabView didTearOffIntoWindowController:(HTMLOutputWindowController*)controller; // the whole strip left for a window of its own
@end

// Several HTML output views behind one tab strip. Only the selected view is
// shown; every view keeps its own page, history, environment and command.
@interface OakHTMLOutputTabView : NSView <OakTabBarViewDataSource, OakTabBarViewDelegate>
@property (nonatomic, weak) id <OakHTMLOutputTabViewDelegate> delegate;
@property (nonatomic, readonly) OakTabBarView* tabBarView;
@property (nonatomic, readonly) NSView* tabStripView; // the grip and the tab bar together
@property (nonatomic) BOOL hostsTabBar; // NO when the owner places the strip itself, e.g. in the title bar

@property (nonatomic, readonly) NSArray<OakHTMLOutputView*>* htmlOutputViews;
@property (nonatomic) OakHTMLOutputView* selectedHTMLOutputView;

- (void)addHTMLOutputView:(OakHTMLOutputView*)aView; // appends and selects
- (OakHTMLOutputView*)htmlOutputViewForIdentifier:(NSUUID*)aCommandIdentifier busy:(BOOL)busyFlag;
- (OakHTMLOutputView*)htmlOutputViewForDocumentPath:(NSString*)aPath; // the view whose page was produced for the document // a reusable view showing the command, a running one only when asked
- (void)insertHTMLOutputView:(OakHTMLOutputView*)aView atIndex:(NSUInteger)anIndex; // takes the view from any other strip, keeping it on screen throughout
- (void)removeHTMLOutputView:(OakHTMLOutputView*)aView;
- (HTMLOutputWindowController*)tearOffHTMLOutputView:(OakHTMLOutputView*)aView atScreenPoint:(NSPoint)aPoint; // moves the view into a new window there
- (void)moveHTMLOutputViewsToTabView:(OakHTMLOutputTabView*)aTabView; // every tab, in order, selection included
- (HTMLOutputWindowController*)tearOffAllHTMLOutputViewsAtScreenPoint:(NSPoint)aPoint;

// Asks to stop each running command in turn; didStopAll is NO when the user keeps one running
- (void)stopRunningCommandsWithCompletionHandler:(void(^)(BOOL didStopAll))handler;

// Selects the tab holding the view. Reachable from the view through the responder chain.
- (void)revealHTMLOutputView:(OakHTMLOutputView*)aView;
@end
