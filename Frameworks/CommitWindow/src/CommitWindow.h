static NSString* const kOakCommitWindowClientPortName       = @"clientPortName";
static NSString* const kOakCommitWindowArguments            = @"arguments";
static NSString* const kOakCommitWindowEnvironment          = @"environment";
static NSString* const kOakCommitWindowStandardOutput       = @"stdout";
static NSString* const kOakCommitWindowStandardError        = @"stderr";
static NSString* const kOakCommitWindowReturnCode           = @"returnCode";
static NSString* const kOakCommitWindowContinue             = @"continue";

// The tool sends its arguments and environment to the app's port and waits for the result on a port of its own (see OakMessagePort.h).
@interface OakCommitWindowServer : NSObject
@property (class, readonly) OakCommitWindowServer* sharedInstance;
- (void)connectFromClientWithOptions:(NSDictionary*)someOptions;
@end
