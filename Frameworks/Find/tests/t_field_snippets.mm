#import "../src/FFTextFieldViewController Private.h"
#import <OakAppKit/OakPasteboard.h>
#import <test/bundle_index.h>

// Snippet expansion in the find/replace fields: the field answers the
// bundle system (scope + snippet insertion) through the responder chain,
// with tab-stop navigation and live mirrors driven by snippet::stack_t.

static bundles::item_ptr MakeItem (bundles::kind_t kind, std::string const& plist)
{
	static test::bundle_index_t index;
	return index.add(kind, plist);
}

static NSTextField* EditingField (FFTextFieldViewController** outController, NSWindow** outWindow, NSTextView** outEditor)
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:OakPasteboard.findPasteboard grammarName:@"source.regexp.oniguruma"];
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	NSTextField* field = (NSTextField*)controller.view;
	field.frame = NSMakeRect(10, 10, 380, 24);
	[window.contentView addSubview:field];
	[window makeFirstResponder:field];
	[field selectText:nil];
	if(outController)
		*outController = controller;
	if(outWindow)
		*outWindow = window;
	if(outEditor)
		*outEditor = (NSTextView*)field.currentEditor;
	return field;
}

void test_field_editor_chain_reaches_field ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	NSTextField* field = EditingField(&controller, &window, &editor);
	OAK_ASSERT(editor != nil);

	Class fieldClass = NSClassFromString(@"OakAutoSizingTextField");
	OAK_ASSERT(fieldClass != nil);
	OAK_ASSERT([field isKindOfClass:fieldClass]);

	// Bundle-item execution finds the field via targetForAction:, so the
	// field must be in the field editor’s responder chain.
	NSResponder* responder = editor;
	BOOL found = NO;
	for(int i = 0; i < 50 && responder; ++i)
	{
		responder = responder.nextResponder;
		if(responder == field)
		{
			found = YES;
			break;
		}
	}
	OAK_ASSERT(found);
}

void test_field_scope_matches_regexp_selector ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:OakPasteboard.findPasteboard grammarName:@"source.regexp.oniguruma"];
	scope::context_t scope = [controller scopeContextForField];
	OAK_ASSERT(to_s(scope.right) == "source.regexp.oniguruma");

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = 'x'; scope = 'source.regexp.oniguruma'; }");
	OAK_ASSERT(item->scope_selector().does_match(scope).has_value());
}

void test_snippet_expands_with_first_stop_selected ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '(?<=${1:look_behind_for})'; }");
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT([editor.string isEqualToString:@"(?<=look_behind_for)"]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(4, 15)));
}

void test_tab_navigates_stops_then_falls_through ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	NSTextField* field = EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '(?''${1:AA}''${2:BB})'; }");
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(3, 2)));

	// Shift-Tab on the first stop falls through to field navigation.
	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertBacktab:)] == NO);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(3, 2)));

	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == YES);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(6, 2)));

	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertBacktab:)] == YES);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(3, 2)));

	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == YES);
	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == YES);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(9, 0))); // implicit $0

	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == NO);
}

void test_mirror_tracks_typing ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '(?''${1:group_name}''${2:reg_exp}) \\k<$1>'; }");
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(3, 10)));

	[editor insertText:@"xy"];
	OAK_ASSERT([editor.string isEqualToString:@"(?'xy'reg_exp) \\k<xy>"]);
}

void test_mirror_before_stop_updates ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	// Transform mirror ahead of its field: the engine prepends it, so the
	// echoed edit is not at index 0 of the replacement vector. The mirror
	// changing length must also move the caret, or Tab drops the session.
	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '${1/(.*)/$1/} ${1:x} ${2:y}'; }");
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT([editor.string isEqualToString:@"x x y"]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(2, 1)));

	[editor insertText:@"yz"];
	OAK_ASSERT([editor.string isEqualToString:@"yz yz y"]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(5, 0)));

	NSTextField* field = (NSTextField*)controller.view;
	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == YES);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(6, 1)));
}

void test_mirror_tracks_consecutive_typing ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '${1/(.*)/$1/} ${1:x}'; }");
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(2, 1)));

	[editor insertText:@"F"];
	OAK_ASSERT([editor.string isEqualToString:@"F F"]);
	[editor insertText:@"O"];
	OAK_ASSERT([editor.string isEqualToString:@"FO FO"]);
	[editor insertText:@"O"];
	OAK_ASSERT([editor.string isEqualToString:@"FOO FOO"]);
	[editor deleteBackward:nil];
	OAK_ASSERT([editor.string isEqualToString:@"FO FO"]);
}

void test_multiline_snippet_tracks_consecutive_typing ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	// The C include-guard shape: multi-line, char-class transform mirror
	// ahead of a long default stop.
	static test::bundle_index_t index;
	plist::dictionary_t plist;
	plist["content"] = std::string("#ifndef ${1/([A-Za-z0-9_]+).*/$1/}\n#define ${1:SYMBOL} ${2:value}\n#endif");
	bundles::item_ptr item = index.add(bundles::kItemTypeSnippet, plist);
	OAK_ASSERT([controller expandBundleItem:item]);
	OAK_ASSERT(NSEqualRanges(editor.selectedRange, NSMakeRange(23, 6)));

	for(char c : std::string("FOO_H"))
		[editor insertText:[NSString stringWithFormat:@"%c", c]];
	OAK_ASSERT([editor.string isEqualToString:@"#ifndef FOO_H\n#define FOO_H value\n#endif"]);
}

void test_edit_outside_snippet_drops_session ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	NSTextField* field = EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeSnippet, "{ content = '(?<=${1:X})'; }");
	OAK_ASSERT([controller expandBundleItem:item]);

	editor.selectedRange = NSMakeRange(0, 0);
	[editor insertText:@"!"];
	OAK_ASSERT([editor.string isEqualToString:@"!(?<=X)"]);
	OAK_ASSERT([controller control:field textView:editor doCommandBySelector:@selector(insertTab:)] == NO);
}

void test_field_reports_selection_state ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	NSTextField* field = EditingField(&controller, &window, &editor);

	OAK_ASSERT([[field valueForKey:@"hasSelection"] boolValue] == NO);
	[editor insertText:@"hello"];
	editor.selectedRange = NSMakeRange(1, 3);
	OAK_ASSERT([[field valueForKey:@"hasSelection"] boolValue] == YES);
	editor.selectedRange = NSMakeRange(5, 0);
	OAK_ASSERT([[field valueForKey:@"hasSelection"] boolValue] == NO);
}

void test_plain_text_field_answers_no_bundle_api ()
{
	// Our field subclass adds TextMate bundle API (scopeContext,
	// performBundleItem:, hasSelection). Plain fields must implement none
	// of it (nor validateMenuItem:, which the menu-validation fall-through
	// relies on skipping); if AppKit ever adds one of these, the override
	// semantics need review.
	NSTextField* field = [[NSTextField alloc] init];
	OAK_ASSERT([field respondsToSelector:@selector(scopeContext)] == NO);
	OAK_ASSERT([field respondsToSelector:@selector(performBundleItem:)] == NO);
	OAK_ASSERT([field respondsToSelector:@selector(hasSelection)] == NO);
	OAK_ASSERT([field respondsToSelector:@selector(validateMenuItem:)] == NO);
}

void test_non_snippet_item_is_not_expanded ()
{
	FFTextFieldViewController* controller = nil;
	NSWindow* window = nil;
	NSTextView* editor = nil;
	EditingField(&controller, &window, &editor);

	bundles::item_ptr item = MakeItem(bundles::kItemTypeCommand, "{ command = 'true'; }");
	OAK_ASSERT([controller expandBundleItem:item] == NO);
	OAK_ASSERT([editor.string isEqualToString:@""]);
}
