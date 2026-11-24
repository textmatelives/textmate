#import "OakAccessibleLinkTesting.h"

static OakAccessibleLink* makeLink ()
{
	return [[OakAccessibleLink alloc] initWithTextView:nil range:ng::range_t(ng::index_t(0), ng::index_t(5)) title:@"hello" URL:@"url" frame:NSZeroRect];
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

// A link answers the attributes it supports and stays quiet about the rest.
// It used to throw NSAccessibilityException for anything unknown, which the
// app-wide exception handler turns into abort() before AppKit can catch it
// (issue #176).
void test_supported_attributes_still_answer ()
{
	OakAccessibleLink* element = makeLink();
	OAK_ASSERT([[element accessibilityAttributeValue:NSAccessibilityTitleAttribute] isEqualToString:@"hello"]);
	OAK_ASSERT([[element accessibilityAttributeValue:NSAccessibilityURLAttribute] isEqualToString:@"url"]);
	OAK_ASSERT([[element accessibilityAttributeValue:NSAccessibilityRoleAttribute] isEqualToString:NSAccessibilityLinkRole]);
}

void test_unknown_attribute_returns_nil_without_throwing ()
{
	OakAccessibleLink* element = makeLink();
	__block id value = @"unset";
	OAK_ASSERT(exceptionFrom(^{ value = [element accessibilityAttributeValue:NSAccessibilityFocusedAttribute]; }) == nil);
	OAK_ASSERT(value == nil);
	OAK_ASSERT(exceptionFrom(^{ value = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute]; }) == nil);
	OAK_ASSERT(value == nil);
}

void test_unknown_parameterized_attribute_returns_nil_without_throwing ()
{
	OakAccessibleLink* element = makeLink();
	__block id value = @"unset";
	OAK_ASSERT(exceptionFrom(^{ value = [element accessibilityAttributeValue:NSAccessibilityStringForRangeParameterizedAttribute forParameter:[NSValue valueWithRange:NSMakeRange(0, 1)]]; }) == nil);
	OAK_ASSERT(value == nil);
}

void test_setting_a_read_only_attribute_is_ignored ()
{
	OakAccessibleLink* element = makeLink();
	OAK_ASSERT(exceptionFrom(^{ [element accessibilitySetValue:@"other" forAttribute:NSAccessibilityTitleAttribute]; }) == nil);
	OAK_ASSERT([[element accessibilityAttributeValue:NSAccessibilityTitleAttribute] isEqualToString:@"hello"]);
}

void test_unknown_action_is_ignored ()
{
	OakAccessibleLink* element = makeLink();
	OAK_ASSERT(exceptionFrom(^{ [element accessibilityPerformAction:NSAccessibilityIncrementAction]; }) == nil);
}
