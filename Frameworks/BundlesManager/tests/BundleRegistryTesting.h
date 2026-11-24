#import "../src/BundleRegistry.h"

// Private registry steps the tests drive directly. Lives in a header because
// gen_test wraps test bodies in a namespace and Objective-C declarations must
// be global.
@interface BundleRegistry (Testing)
- (void)seedMandatory;
@end
