#import "FFTextFieldViewController.h"
#include <bundles/bundles.h>
#include <scope/scope.h>

// Test-visible subset of the field controller’s snippet support.
@interface FFTextFieldViewController (SnippetSupport)
- (NSString*)grammarName;
- (scope::context_t)scopeContextForField;
- (BOOL)expandBundleItem:(bundles::item_ptr)item;
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command;
@end
