#import <OakTabBarView/OakTabBarView.h>

typedef NS_ENUM(NSInteger, ProjectLayoutHTMLOutputPlacement) {
	ProjectLayoutHTMLOutputBelow = 0,
	ProjectLayoutHTMLOutputRight,
	ProjectLayoutHTMLOutputLeft,
};

@interface ProjectLayoutView : NSView
@property (nonatomic) NSView* documentView;
@property (nonatomic) NSView* fileBrowserView;
@property (nonatomic) NSView* htmlOutputView;

@property (nonatomic) CGFloat fileBrowserWidth;
@property (nonatomic) BOOL fileBrowserOnRight;

@property (nonatomic) NSSize htmlOutputSize; // width counts beside the text view, height below it
@property (nonatomic) ProjectLayoutHTMLOutputPlacement htmlOutputPlacement; // set by the window; the preference only seeds new windows
@end
