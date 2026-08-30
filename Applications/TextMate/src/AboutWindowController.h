@interface AboutWindowController : NSWindowController
@property (class, readonly) AboutWindowController* sharedInstance;
+ (void)showUpdateNoticeIfNeeded;
- (void)showAboutWindow:(id)sender;
- (void)showChangesWindow:(id)sender;
@end
