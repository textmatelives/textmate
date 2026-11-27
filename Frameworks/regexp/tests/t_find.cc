#include <regexp/find.h>

typedef std::pair<size_t, size_t> range_t;

static std::vector<range_t> all_matches (find::find_t matcher, std::string const& text)
{
	std::vector<range_t> res;
	matcher.each_match(text.data(), text.size(), false /* no more data */, [&res](std::pair<size_t, size_t> const& m, std::map<std::string, std::string> const& captures){
		res.push_back(m);
	});
	return res;
}

// Feed text as chunks ending at splits (OakDocument style: data chunks with
// more data, then a nullptr terminator), e.g. { 3, 7 } → [0,3) [3,7) [7,end).
static std::vector<range_t> chunked_matches (find::find_t matcher, std::string const& text, std::vector<size_t> const& splits)
{
	std::vector<range_t> res;
	auto collect = [&res](std::pair<size_t, size_t> const& m, std::map<std::string, std::string> const& captures){
		res.push_back(m);
	};
	size_t prev = 0;
	for(size_t end : splits)
	{
		matcher.each_match(text.data() + prev, end - prev, true /* more data */, collect);
		prev = end;
	}
	matcher.each_match(text.data() + prev, text.size() - prev, true /* more data */, collect);
	matcher.each_match(nullptr, 0, false /* no more data */, collect);
	return res;
}

void test_regular_backward ()
{
	find::find_t matcher("var = ");
	std::vector<range_t> ranges = all_matches(matcher, "var = 32 && var = 5;");

	OAK_ASSERT_EQ(ranges.size(), 2);
	OAK_ASSERT_EQ(ranges[0], range_t(0, 6));
	OAK_ASSERT_EQ(ranges[1], range_t(12, 18));
}

void test_regexp_backward ()
{
	find::find_t matcher("text::(lower|upper)", find::regular_expression);
	std::vector<range_t> ranges = all_matches(matcher, "Lorem text::uppercase ipsum.");

	OAK_ASSERT_EQ(ranges.size(), 1);
	OAK_ASSERT_EQ(ranges[0], range_t(6, 17));
}

void test_full_words_basic ()
{
	find::find_t matcher("foo", find::full_words);
	std::vector<range_t> ranges = all_matches(matcher, "foo bar foobar foo-bar foo_bar foo.");

	OAK_ASSERT_EQ(ranges.size(), 3);
	OAK_ASSERT_EQ(ranges[0], range_t(0, 3));   // leading start-of-buffer
	OAK_ASSERT_EQ(ranges[1], range_t(15, 18)); // '-' is a boundary …
	OAK_ASSERT_EQ(ranges[2], range_t(31, 34)); // … but '_' is a word char (foo_bar skipped)
}

void test_full_words_stream_edges ()
{
	OAK_ASSERT_EQ(all_matches(find::find_t("foo", find::full_words), "foo").size(), 1);      // whole stream
	OAK_ASSERT_EQ(all_matches(find::find_t("foo", find::full_words), "foo")[0], range_t(0, 3));
	OAK_ASSERT(all_matches(find::find_t("foo", find::full_words), "afoo").empty());           // leading word char
	OAK_ASSERT(all_matches(find::find_t("foo", find::full_words), "fooa").empty());           // trailing word char
	OAK_ASSERT_EQ(all_matches(find::find_t("foo", find::full_words), " foo ")[0], range_t(1, 4));
}

void test_full_words_unicode ()
{
	// 'é' is U+00E9, two bytes in UTF-8.
	std::vector<range_t> ranges = all_matches(find::find_t("caf\xC3\xA9", find::full_words), "caf\xC3\xA9 xcaf\xC3\xA9 caf\xC3\xA9_ caf\xC3\xA9");
	OAK_ASSERT_EQ(ranges.size(), 2);
	OAK_ASSERT_EQ(ranges[0], range_t(0, 5));
	OAK_ASSERT_EQ(ranges[1], range_t(20, 25));

	// Multibyte word chars as neighbors must also reject the match.
	ranges = all_matches(find::find_t("foo", find::full_words), "\xC3\xA9" "foo foo" "\xC3\xA9" " foo");
	OAK_ASSERT_EQ(ranges.size(), 1);
	OAK_ASSERT_EQ(ranges[0], range_t(12, 15));
}

void test_full_words_case_insensitive ()
{
	find::find_t matcher("Foo", (find::options_t)(find::full_words|find::ignore_case));
	std::vector<range_t> ranges = all_matches(matcher, "foo FOO foobar");

	OAK_ASSERT_EQ(ranges.size(), 2);
	OAK_ASSERT_EQ(ranges[0], range_t(0, 3));
	OAK_ASSERT_EQ(ranges[1], range_t(4, 7));
}

void test_full_words_ignored_for_regexp ()
{
	// Regexp users write \b themselves; the flag must not disturb that path.
	find::find_t matcher("\\bfoo\\b", (find::options_t)(find::regular_expression|find::full_words));
	std::vector<range_t> ranges = all_matches(matcher, "foo foobar");

	OAK_ASSERT_EQ(ranges.size(), 1);
	OAK_ASSERT_EQ(ranges[0], range_t(0, 3));
}

void test_full_words_ignored_when_backwards ()
{
	// No caller feeds find_t backwards; the filter degrades to passthrough.
	find::find_t matcher("foo", (find::options_t)(find::full_words|find::backwards));
	std::vector<range_t> ranges = all_matches(matcher, "foobar");

	OAK_ASSERT_EQ(ranges.size(), 1); // unfiltered, like without the flag
	OAK_ASSERT_EQ(ranges[0], range_t(0, 3));
}

void test_full_words_chunk_split ()
{
	// Split inside matches, boundaries and neighbors: same result as one chunk.
	std::string const text = "afoo foo foob";
	std::vector<range_t> expected = all_matches(find::find_t("foo", find::full_words), text);
	OAK_ASSERT_EQ(expected.size(), 1);
	OAK_ASSERT_EQ(expected[0], range_t(5, 8));

	for(size_t a = 1; a < text.size(); ++a)
	{
		for(size_t b = a + 1; b < text.size(); ++b)
		{
			std::vector<range_t> ranges = chunked_matches(find::find_t("foo", find::full_words), text, { a, b });
			OAK_ASSERT_EQ(ranges.size(), 1);
			if(!ranges.empty())
				OAK_ASSERT_EQ(ranges[0], range_t(5, 8));
		}
	}
}

void test_full_words_chunk_split_unicode ()
{
	// Split inside the multibyte neighbor itself: trailing 'é' arrives byte
	// by byte, leading 'é' sits in a previous chunk.
	std::string const text = "\xC3\xA9" "foo foo" "\xC3\xA9";
	for(size_t a = 1; a < text.size(); ++a)
	{
		for(size_t b = a + 1; b < text.size(); ++b)
		{
			std::vector<range_t> ranges = chunked_matches(find::find_t("foo", find::full_words), text, { a, b });
			OAK_ASSERT(ranges.empty());
		}
	}

	// … and a whole word split across chunks still matches.
	std::vector<range_t> ranges = chunked_matches(find::find_t("foo", find::full_words), "x foo y", { 3, 4 });
	OAK_ASSERT_EQ(ranges.size(), 1);
	OAK_ASSERT_EQ(ranges[0], range_t(2, 5));
}

void test_full_words_chunk_edge_at_stream_end ()
{
	// Match ending exactly at the last chunk edge still matches (OakDocument
	// style: data chunks, then a nullptr terminator).
	std::vector<range_t> ranges = chunked_matches(find::find_t("foo", find::full_words), " foo", { 2 });
	OAK_ASSERT_EQ(ranges.size(), 1);
	OAK_ASSERT_EQ(ranges[0], range_t(1, 4));

	// … but a trailing char truncated by the stream end fails closed.
	ranges = chunked_matches(find::find_t("foo", find::full_words), " foo\xC3", { 2 });
	OAK_ASSERT(ranges.empty());
}
