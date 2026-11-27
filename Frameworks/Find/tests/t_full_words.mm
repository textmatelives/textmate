#import <Find/Find.h>

// The Whole Words checkbox binds to the private fullWords/canFullWords
// properties; reach them via KVC like t_search_target.mm does.

static BOOL FullWords (Find* find)
{
	return [[find valueForKey:@"fullWords"] boolValue];
}

static BOOL CanFullWords (Find* find)
{
	return [[find valueForKey:@"canFullWords"] boolValue];
}

void test_full_words_masked_when_regexp ()
{
	Find* find = [[Find alloc] init];
	OAK_ASSERT(FullWords(find) == NO); // off by default

	[find setValue:@YES forKey:@"fullWords"];
	OAK_ASSERT(FullWords(find) == YES);
	OAK_ASSERT(CanFullWords(find) == YES);

	[find setValue:@YES forKey:@"regularExpression"];
	OAK_ASSERT(CanFullWords(find) == NO);
	OAK_ASSERT(FullWords(find) == NO); // stale YES is masked …

	[find setValue:@NO forKey:@"regularExpression"];
	OAK_ASSERT(FullWords(find) == YES); // … but preserved
}

void test_full_words_menu_toggle ()
{
	Find* find = [[Find alloc] init];
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Whole Words" action:@selector(toggleFindOption:) keyEquivalent:@""];
	item.tag = 1; // find::full_words

	[find takeFindOptionToToggleFrom:item];
	OAK_ASSERT(FullWords(find) == YES);
	[find takeFindOptionToToggleFrom:item];
	OAK_ASSERT(FullWords(find) == NO);
}

static NSButton* FindCheckBoxWithTitle (NSView* view, NSString* title)
{
	if([view isKindOfClass:[NSButton class]] && [[(NSButton*)view title] isEqualToString:title])
		return (NSButton*)view;
	for(NSView* subview in view.subviews)
	{
		if(NSButton* found = FindCheckBoxWithTitle(subview, title))
			return found;
	}
	return nil;
}

void test_full_words_check_box_is_bound ()
{
	Find* find = [[Find alloc] init];
	NSButton* checkBox = FindCheckBoxWithTitle(find.window.contentView, @"Whole Words");
	OAK_ASSERT(checkBox != nil);
	OAK_ASSERT([[[checkBox infoForBinding:NSValueBinding] objectForKey:NSObservedKeyPathKey] isEqualToString:@"content.fullWords"]);
	OAK_ASSERT([[[checkBox infoForBinding:NSEnabledBinding] objectForKey:NSObservedKeyPathKey] isEqualToString:@"content.canFullWords"]);

	[checkBox performClick:nil]; // end to end: click the box, the property flips
	OAK_ASSERT(FullWords(find) == YES);
	[checkBox performClick:nil];
	OAK_ASSERT(FullWords(find) == NO);

	[find setValue:@YES forKey:@"regularExpression"];
	OAK_ASSERT(checkBox.enabled == NO);
}
