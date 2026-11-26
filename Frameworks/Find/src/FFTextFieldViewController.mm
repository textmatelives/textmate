#import "FFTextFieldViewController.h"
#import <OakAppKit/OakSyntaxFormatter.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakPasteboardSelector.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <bundles/bundles.h>
#import <ns/ns.h>
#import <plist/plist.h>
#import <regexp/snippet.h>
#import <scope/scope.h>

// ==========================
// = OakAutoSizingTextField =
// ==========================

#import "FFTextFieldViewController Private.h"

@interface OakAutoSizingTextField : NSTextField
@property (nonatomic) NSSize myIntrinsicContentSize;
@property (nonatomic, weak) FFTextFieldViewController* fieldController;
- (scope::context_t)scopeContext;
- (BOOL)hasSelection;
- (void)performBundleItem:(bundles::item_ptr)item;
@end

@implementation OakAutoSizingTextField
- (NSSize)intrinsicContentSize
{
	return NSEqualSizes(self.myIntrinsicContentSize, NSZeroSize) ? [super intrinsicContentSize] : self.myIntrinsicContentSize;
}

- (void)updateIntrinsicContentSizeToEncompassString:(NSString*)aString
{
	NSTextFieldCell* cell = [self.cell copy];
	cell.stringValue = aString ?: @"";

	self.myIntrinsicContentSize = NSMakeSize(NSViewNoIntrinsicMetric, MAX(22, MIN([cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth([self bounds]), CGFLOAT_MAX)].height, 225)));
	[self invalidateIntrinsicContentSize];
}

// The field answers the bundle system with its grammar scope (e.g. the
// find field reports source.regexp.oniguruma) so the bundle-item chooser
// and scope-gated key equivalents treat it like a scoped text view.
- (scope::context_t)scopeContext
{
	return [self.fieldController scopeContextForField];
}

// Required by showBundleItemChooser:, which calls OakTextView API on
// whatever answers scopeContext.
- (BOOL)hasSelection
{
	NSTextView* editor = (NSTextView*)self.currentEditor;
	return [editor isKindOfClass:[NSTextView class]] && editor.selectedRange.length > 0;
}

// Menu / chooser snippet execution reaches us through the responder chain
// (field editor → field) instead of falling through to the frontmost
// document window.
- (void)performBundleItem:(bundles::item_ptr)item
{
	if([self.fieldController expandBundleItem:item])
		return;

	// Preserve legacy routing (frontmost document) for anything we don’t expand.
	NSWindow* mainWindow = NSApp.mainWindow;
	id target = mainWindow && mainWindow != self.window && [mainWindow.delegate respondsToSelector:@selector(performBundleItem:)] ? mainWindow.delegate : nil;
	if(!target && [NSApp.delegate respondsToSelector:@selector(performBundleItem:)])
		target = NSApp.delegate;
	[target performBundleItem:item];
}
@end

// =============================
// = FFTextFieldViewController =
// =============================

static void* kFirstResponderContext = &kFirstResponderContext;

@interface FFTextFieldViewController () <NSTextFieldDelegate, NSTextStorageDelegate, NSPopoverDelegate>
{
	OakAutoSizingTextField* _textField;
	OakSyntaxFormatter*     _syntaxFormatter;
	OakPasteboard*          _pasteboard;
	NSString*               _grammarName;
	NSPopover*              _popover;

	// Active snippet session (mirrors ng::snippet_controller_t): the stack
	// works in snippet-relative byte offsets, _snippetAnchor is the byte
	// offset of the snippet start in the field.
	snippet::stack_t _snippets;
	size_t           _snippetAnchor;
	BOOL             _applyingSnippet;
	NSString*        _lastKnownString;
}
@end

// The snippet engine works in UTF-8 byte offsets, the field editor in
// UTF-16 units. Conversions clamp or fail soft (NSNotFound) so exotic
// content degrades to “no snippet session” instead of corrupting text.
static size_t UTF16ToBytes (NSString* str, NSUInteger loc)
{
	return [[str substringToIndex:MIN(loc, str.length)] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

static NSUInteger BytesToUTF16 (NSString* str, size_t byteOffset)
{
	NSData* data = [str dataUsingEncoding:NSUTF8StringEncoding];
	if(byteOffset > data.length)
		return NSNotFound;
	NSString* prefix = [[NSString alloc] initWithBytes:data.bytes length:byteOffset encoding:NSUTF8StringEncoding];
	return prefix ? prefix.length : NSNotFound;
}

@implementation FFTextFieldViewController
- (instancetype)initWithPasteboard:(OakPasteboard*)pasteboard grammarName:(NSString*)grammarName
{
	if(self = [self initWithNibName:nil bundle:nil])
	{
		_pasteboard  = pasteboard;
		_grammarName = grammarName;
	}
	return self;
}

- (void)showHistory:(id)sender
{
	if(!OakPasteboardSelector.sharedInstance.window.isVisible)
		[_pasteboard selectItemForControl:_textField];
}

- (void)showPopoverWithString:(NSString*)aString
{
	if(aString)
	{
		if(!_popover)
		{
			NSViewController* viewController = [[NSViewController alloc] init];
			viewController.view = OakCreateLabel();

			_popover = [[NSPopover alloc] init];
			_popover.behavior = NSPopoverBehaviorTransient;
			_popover.contentViewController = viewController;
			_popover.delegate = self;
		}

		NSTextField* textField = (NSTextField*)_popover.contentViewController.view;
		textField.stringValue = aString;
		[textField sizeToFit];

		[_popover showRelativeToRect:NSZeroRect ofView:_textField preferredEdge:NSMaxYEdge];
	}
	else
	{
		[_popover close];
		_popover = nil;
	}
}

- (void)popoverDidClose:(NSNotification*)aNotification
{
	_popover = nil;
}

- (void)setSyntaxHighlightEnabled:(BOOL)flag
{
	if(_syntaxHighlightEnabled == flag)
		return;

	_syntaxHighlightEnabled  = flag;
	_syntaxFormatter.enabled = flag;

	// Re-format current value
	if(!_textField.currentEditor)
	{
		NSString* currentString = [_textField.stringValue copy];
		_textField.objectValue = nil;
		_textField.objectValue = currentString;
	}

	[self addStylesToFieldEditor];
}

- (OakSyntaxFormatter*)syntaxFormatter
{
	if(!_syntaxFormatter)
		_syntaxFormatter = [[OakSyntaxFormatter alloc] initWithGrammarName:_grammarName];
	return _syntaxFormatter;
}

- (OakAutoSizingTextField*)textField
{
	if(!_textField)
	{
		_textField = [[OakAutoSizingTextField alloc] initWithFrame:NSZeroRect];
		_textField.font       = OakControlFont();
		_textField.formatter  = self.syntaxFormatter;
		_textField.delegate   = self;
		_textField.cell.wraps = YES;
		_textField.fieldController = self;
	}
	return _textField;
}

- (NSString*)grammarName
{
	return _grammarName;
}

- (scope::context_t)scopeContextForField
{
	return _grammarName ? scope::context_t(to_s(_grammarName)) : scope::context_t();
}

- (void)loadView
{
	self.view = self.textField;
}

- (void)viewDidAppear
{
	[self.view.window addObserver:self forKeyPath:@"firstResponder" options:0 context:kFirstResponderContext];
	[self.textField bind:NSValueBinding toObject:self withKeyPath:@"stringValue" options:@{ NSContinuouslyUpdatesValueBindingOption: @YES }];
}

- (void)viewWillDisappear
{
	[self.textField unbind:NSValueBinding];
	[self.view.window removeObserver:self forKeyPath:@"firstResponder" context:kFirstResponderContext];
}

- (void)setStringValue:(NSString*)newStringValue
{
	if([_stringValue isEqualToString:newStringValue])
		return;
	_stringValue = newStringValue;
	[self showPopoverWithString:nil];
	[_textField updateIntrinsicContentSizeToEncompassString:newStringValue];

	if(NSDictionary* info = [self infoForBinding:@"stringValue"])
	{
		id controller     = info[NSObservedObjectKey];
		NSString* keyPath = info[NSObservedKeyPathKey];
		if(controller && controller != [NSNull null] && keyPath && (id)keyPath != [NSNull null])
		{
			id oldValue = [controller valueForKeyPath:keyPath];
			if(!oldValue || ![oldValue isEqual:newStringValue])
				[controller setValue:newStringValue forKeyPath:keyPath];
		}
	}
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == kFirstResponderContext)
	{
		id firstResponder = self.view.window.firstResponder;
		self.hasFocus = firstResponder == _textField || firstResponder == _textField.currentEditor;
	}
}

- (void)setHasFocus:(BOOL)flag
{
	_hasFocus = flag;
	if(_hasFocus && [_textField.currentEditor isKindOfClass:[NSTextView class]])
	{
		NSTextView* textView = (NSTextView*)_textField.currentEditor;
		textView.textStorage.delegate = self;
		[self addStylesToFieldEditor];
	}
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command
{
	if(command == @selector(insertTab:) || command == @selector(insertBacktab:))
	{
		// Tab navigates tab stops only while a snippet session is active;
		// otherwise it keeps its field-navigation behavior.
		if(!_snippets.empty())
		{
			size_t caretB = UTF16ToBytes(textView.string, NSMaxRange(textView.selectedRange));
			if(caretB < _snippetAnchor)
				_snippets.clear();
			else	_snippets.drop_for_pos(caretB - _snippetAnchor);

			BOOL moved = command == @selector(insertTab:) ? _snippets.next() : _snippets.previous();
			if(moved)
				[self selectSnippetRange:_snippets.current() inEditor:textView];
			return moved;
		}
	}
	else if(command == @selector(moveDown:))
	{
		NSRange lastNewline    = [textView.string rangeOfString:@"\n" options:NSBackwardsSearch];
		NSRange insertionPoint = textView.selectedRanges.lastObject.rangeValue;

		if(lastNewline.location == NSNotFound || lastNewline.location < NSMaxRange(insertionPoint))
			return [self showHistory:self], YES;
	}
	return NO;
}

- (BOOL)selectSnippetRange:(snippet::range_t const&)range inEditor:(NSTextView*)editor
{
	NSString* str = editor.string;
	NSUInteger from = BytesToUTF16(str, range.from.offset + _snippetAnchor);
	NSUInteger to   = BytesToUTF16(str, range.to.offset + _snippetAnchor);
	if(from == NSNotFound || to == NSNotFound || to < from || to > str.length)
	{
		_snippets.clear();
		return NO;
	}
	editor.selectedRange = NSMakeRange(from, to - from);
	return YES;
}

- (BOOL)expandBundleItem:(bundles::item_ptr)item
{
	if(!item || item->kind() != bundles::kItemTypeSnippet)
		return NO;

	std::string content;
	if(!plist::get_key_path(item->plist(), "content", content))
		return NO;

	NSTextView* editor = (NSTextView*)_textField.currentEditor;
	if(![editor isKindOfClass:[NSTextView class]])
	{
		// Not editing (unexpected via the responder chain): start and retry once.
		[_textField.window makeFirstResponder:_textField];
		editor = (NSTextView*)_textField.currentEditor;
		if(![editor isKindOfClass:[NSTextView class]])
			return NO;
	}

	// Mirror tracking needs storage callbacks; ensure the delegate even if
	// viewDidAppear never ran (the field controllers have no containment).
	editor.textStorage.delegate = self;

	NSString* fieldString = editor.string;
	NSRange selection = editor.selectedRange;

	std::map<std::string, std::string> variables = item->bundle_variables();
	variables["TM_SCOPE"] = to_s(_grammarName);
	variables["TM_SELECTED_TEXT"] = to_s([fieldString substringWithRange:selection]);

	// No run-command callback (shell code in snippets is dropped) and no
	// choice UI (first choice is inserted as an editable default).
	snippet::snippet_t const& snippet = snippet::parse(content, variables, "", text::indent_t(), nullptr);

	size_t fromB = UTF16ToBytes(fieldString, selection.location);

	_applyingSnippet = YES;
	[editor insertText:to_ns(snippet.text) replacementRange:selection];
	_applyingSnippet = NO;

	_snippets.clear();
	_snippetAnchor = fromB;
	_snippets.push(snippet, snippet::range_t(0, snippet.text.size()));
	_lastKnownString = [editor.string copy];
	[self selectSnippetRange:_snippets.current() inEditor:editor];
	return YES;
}

- (void)textStorageDidProcessEditing:(NSNotification*)aNotification
{
	[self addStylesToFieldEditor];

	// Track the previous string ourselves: the detailed delegate methods
	// don’t fire for field editors (so no range info), and by the time
	// willProcessEditing runs the new text is already in place.
	NSTextStorage* textStorage = (NSTextStorage*)aNotification.object;
	NSString* postString = textStorage.string;
	NSString* preString  = _lastKnownString ?: postString;
	_lastKnownString = [postString copy];

	if(_applyingSnippet || _snippets.empty())
		return;

	NSTextView* editor = (NSTextView*)_textField.currentEditor;
	if(![editor isKindOfClass:[NSTextView class]] || editor.textStorage != textStorage)
	{
		_snippets.clear();
		return;
	}

	// Derive the edit by diffing pre/post strings.
	NSUInteger preLen = preString.length, postLen = postString.length;
	NSUInteger prefix = 0;
	while(prefix < preLen && prefix < postLen && [preString characterAtIndex:prefix] == [postString characterAtIndex:prefix])
		++prefix;
	NSUInteger suffix = 0;
	while(suffix < preLen - prefix && suffix < postLen - prefix && [preString characterAtIndex:preLen-1-suffix] == [postString characterAtIndex:postLen-1-suffix])
		++suffix;
	if(prefix + suffix == preLen && prefix + suffix == postLen)
		return; // attribute-only change

	// Expand to composed-character boundaries so multi-unit characters
	// never split mid-edit.
	NSRange oldRange = [preString rangeOfComposedCharacterSequencesForRange:NSMakeRange(prefix, preLen - prefix - suffix)];
	NSRange newRange = [postString rangeOfComposedCharacterSequencesForRange:NSMakeRange(prefix, postLen - prefix - suffix)];

	size_t locB    = UTF16ToBytes(postString, oldRange.location);
	size_t oldEndB = UTF16ToBytes(preString, NSMaxRange(oldRange));
	std::string newText = to_s([postString substringWithRange:newRange]);
	[self applySnippetEditFrom:locB to:oldEndB replacement:newText editor:editor];
}

- (void)applySnippetEditFrom:(size_t)locB to:(size_t)oldEndB replacement:(std::string const&)newText editor:(NSTextView*)editor
{
	NSTextStorage* textStorage = editor.textStorage;

	// Feed the edit so tab-stop ranges track typing. res[0] echoes the edit
	// itself (already in the buffer); the rest are mirror updates to apply.
	// Edits outside the current stop drop the session inside replace().
	snippet::range_t const echoRange(locB - _snippetAnchor, oldEndB - _snippetAnchor);
	auto res = _snippets.replace(echoRange, newText);

	// Identify the echoed edit by value (range AND string): mirrors ahead
	// of the edit are prepended, so the echo is not necessarily at index 0.
	// A duplicate match is a no-op replace (identical range+string); a
	// mirror can share the range at an insertion point, where only the
	// strings differ.
	BOOL foundEcho = NO;
	for(auto const& entry : res)
	{
		if(entry.first == echoRange && entry.second == newText)
		{
			foundEcho = YES;
			break;
		}
	}
	if(!foundEcho)
	{
		_snippets.clear();
		return;
	}

	_applyingSnippet = YES;
	size_t newEndB = locB + newText.size();
	ssize_t echoDeltaB = (ssize_t)newEndB - (ssize_t)oldEndB;
	ssize_t shift = 0;
	for(size_t i = 0; i < res.size(); ++i)
	{
		if(res[i].first == echoRange && res[i].second == newText)
			continue;

		// Map pre-edit bytes to post-edit bytes. Ranges are ascending and
		// (outside nested snippets) disjoint from the echoed edit.
		size_t preFrom = res[i].first.from.offset + _snippetAnchor;
		size_t preTo   = res[i].first.to.offset + _snippetAnchor;
		ssize_t echoShift = preFrom >= oldEndB ? echoDeltaB : 0;
		ssize_t postFrom = (ssize_t)preFrom + shift + echoShift;
		ssize_t postTo   = (ssize_t)preTo + shift + echoShift;
		if(postFrom < 0 || postTo < 0)
		{
			_snippets.clear();
			break;
		}

		NSString* live = textStorage.string;
		NSUInteger from16 = BytesToUTF16(live, (size_t)postFrom);
		NSUInteger to16   = BytesToUTF16(live, (size_t)postTo);
		if(from16 == NSNotFound || to16 == NSNotFound || to16 < from16)
		{
			_snippets.clear();
			break;
		}

		NSRange range = NSMakeRange(from16, to16 - from16);
		NSString* str = to_ns(res[i].second);
		if([editor shouldChangeTextInRange:range replacementString:str])
		{
			[textStorage replaceCharactersInRange:range withString:str];
			[editor didChangeText];
		}
		shift += (ssize_t)res[i].second.size() - (ssize_t)(postTo - postFrom);
	}
	_applyingSnippet = NO;
}

- (void)addStylesToFieldEditor
{
	[_syntaxFormatter addStylesToString:((NSTextView*)_textField.currentEditor).textStorage];
}
@end
