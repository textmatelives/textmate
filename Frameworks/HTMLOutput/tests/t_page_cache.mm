#import "../src/helpers/OakHTMLOutputPageCache.h"

static NSData* page (char const* text)
{
	return [NSData dataWithBytes:text length:strlen(text)];
}

void test_keeps_the_most_recently_used_pages ()
{
	OakHTMLOutputPageCache* cache = [[OakHTMLOutputPageCache alloc] initWithCapacity:2];
	[cache setData:page("a") forKey:@"a"];
	[cache setData:page("b") forKey:@"b"];
	OAK_ASSERT([cache dataForKey:@"a"] != nil); // touching a makes b the oldest
	[cache setData:page("c") forKey:@"c"];

	OAK_ASSERT([cache dataForKey:@"b"] == nil);
	OAK_ASSERT([cache dataForKey:@"a"] != nil);
	OAK_ASSERT([cache dataForKey:@"c"] != nil);
	OAK_ASSERT(cache.count == 2);
}

void test_replacing_a_page_keeps_one_entry ()
{
	OakHTMLOutputPageCache* cache = [[OakHTMLOutputPageCache alloc] initWithCapacity:2];
	[cache setData:page("old") forKey:@"a"];
	[cache setData:page("new") forKey:@"a"];

	OAK_ASSERT(cache.count == 1);
	OAK_ASSERT_EQ(std::string((char const*)[cache dataForKey:@"a"].bytes, [cache dataForKey:@"a"].length), "new");
}

void test_unknown_pages_are_absent ()
{
	OakHTMLOutputPageCache* cache = [[OakHTMLOutputPageCache alloc] initWithCapacity:2];
	OAK_ASSERT([cache dataForKey:@"missing"] == nil);
}
