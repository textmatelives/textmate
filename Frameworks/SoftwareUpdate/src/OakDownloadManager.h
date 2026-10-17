NS_ASSUME_NONNULL_BEGIN

@interface OakDownloadManager : NSObject
@property (class, readonly) OakDownloadManager* sharedInstance;
@property (nonatomic) NSString* userAgentString;
- (id <NSProgressReporting>)downloadArchiveAtURL:(NSURL*)serverURL forReplacingURL:(nullable NSURL*)localURL completionHandler:(void(^)(NSURL* extractedArchiveURL, NSError* error))completionHandler;
@end

NS_ASSUME_NONNULL_END
