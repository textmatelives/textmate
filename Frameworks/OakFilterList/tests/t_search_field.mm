#import <OakFilterList/ui/SearchField.h>

static NSCell* searchFieldCell ()
{
	OakLinkedSearchField* field = [[OakLinkedSearchField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
	field.stringValue = @"abc";
	return field.cell;
}

// Returns the name of the exception a block throws, or nil.
static NSString* exceptionFrom (void(^block)(void))
{
	@try {
		block();
	}
	@catch(NSException* e) {
		return e.name;
	}
	return nil;
}

// The cell pads the search string with a space on each side for
// accessibility. A client asking for a range beyond that padded string used
// to get NSAccessibilityException, which the app-wide exception handler
// turns into abort() before AppKit can catch it (issue #176).
void test_out_of_range_request_returns_nil_without_throwing ()
{
	NSCell* cell = searchFieldCell();
	NSValue* tooLong = [NSValue valueWithRange:NSMakeRange(0, 50)];

	__block id value = @"unset";
	OAK_ASSERT(exceptionFrom(^{ value = [cell accessibilityAttributeValue:NSAccessibilityStringForRangeParameterizedAttribute forParameter:tooLong]; }) == nil);
	OAK_ASSERT(value == nil);

	value = @"unset";
	OAK_ASSERT(exceptionFrom(^{ value = [cell accessibilityAttributeValue:NSAccessibilityLineForIndexParameterizedAttribute forParameter:@(50)]; }) == nil);
	OAK_ASSERT(value == nil);

	OAK_ASSERT(exceptionFrom(^{ [cell accessibilitySetValue:tooLong forAttribute:NSAccessibilitySelectedTextRangeAttribute]; }) == nil);
}

void test_in_range_request_does_not_throw ()
{
	NSCell* cell = searchFieldCell();
	OAK_ASSERT(exceptionFrom(^{ [cell accessibilityAttributeValue:NSAccessibilityStringForRangeParameterizedAttribute forParameter:[NSValue valueWithRange:NSMakeRange(0, 1)]]; }) == nil);
}
