#import <ns/language.h>

static std::string language_at (std::vector<ns::language_run_t> const& runs, size_t i)
{
	for(auto const& run : runs)
	{
		if(run.first <= i && i < run.last)
			return run.language;
	}
	return "";
}

void test_identify_languages ()
{
	std::string const str = "这个终端很快。東京へ行きます。 It works.";
	std::vector<ns::language_run_t> runs = ns::identify_languages(str);
	OAK_ASSERT(!runs.empty());
	OAK_ASSERT_EQ(runs.front().first, 0);
	OAK_ASSERT_EQ(runs.back().last, str.size());
	OAK_ASSERT_EQ(language_at(runs, 0).substr(0, 2), "zh");
	OAK_ASSERT_EQ(language_at(runs, str.find("東京")), "ja");
	OAK_ASSERT_EQ(language_at(runs, str.find("works")), "en");
}

void test_identify_languages_empty ()
{
	OAK_ASSERT(ns::identify_languages("").empty());
	OAK_ASSERT(ns::identify_languages("42 -- 17").empty());
}

void test_preferred_localization ()
{
	OAK_ASSERT_EQ(ns::preferred_localization({ "fr", "en" }), "en");
	OAK_ASSERT_EQ(ns::preferred_localization({ "fr" }), "fr");
	OAK_ASSERT_EQ(ns::preferred_localization({ }), NULL_STR);
}
