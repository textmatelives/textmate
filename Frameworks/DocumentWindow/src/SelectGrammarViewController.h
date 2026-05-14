@class BundleGrammar;
@class BundleSpec;
@class OakDocumentView;

typedef NS_ENUM(NSInteger, SelectGrammarResponse) {
	SelectGrammarResponseInstall = 0,
	SelectGrammarResponseNotNow,
	SelectGrammarResponseNever,
	SelectGrammarResponseCount
};

@interface SelectGrammarViewController : NSViewController
@property (nonatomic) NSString* documentDisplayName;
- (void)showGrammars:(NSArray<BundleGrammar*>*)grammars forView:(OakDocumentView*)documentView completionHandler:(void(^)(SelectGrammarResponse, BundleGrammar*))callback;

// Spec variant for the on-demand prompt (Phase 2). The candidate bundle is
// not yet installed, so there's no realized Bundle*/BundleGrammar* — just
// the catalogue spec. On Install, calls -[BundlesManager installSpecs:].
- (void)showBundleSpec:(BundleSpec*)spec forView:(OakDocumentView*)documentView completionHandler:(void(^)(SelectGrammarResponse, BundleSpec*))callback;

- (void)dismiss;
@end
