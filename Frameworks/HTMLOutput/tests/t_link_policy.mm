#import "../src/helpers/OakLocalLinkPolicy.h"
#import <test/jail.h>
#import <text/decode.h>

static std::string describe (OakLocalLinkAction action)
{
	switch(action)
	{
		case OakLocalLinkActionLoad:   return "load";
		case OakLocalLinkActionOpen:   return "open";
		case OakLocalLinkActionScroll: return "scroll";
	}
	return "unknown";
}

static NSURL* link_to (test::jail_t const& jail, std::string const& relativePath, NSString* fragment = nil, NSString* scheme = @"tm-file")
{
	NSURLComponents* components = [NSURLComponents new];
	components.scheme   = scheme;
	components.host     = @"";
	components.path     = [NSString stringWithUTF8String:jail.path(relativePath).c_str()];
	components.fragment = fragment;
	return components.URL;
}

static std::string action_for (NSURL* url, BOOL linkActivated, NSString* documentPath = nil)
{
	return describe(OakLocalLinkActionForURL(url, linkActivated, documentPath));
}

void test_only_link_clicks_are_intercepted ()
{
	test::jail_t jail;
	jail.touch("notes.md");

	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md"), NO), "load");
	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md"), YES), "open");
}

void test_web_types_load_in_the_web_view ()
{
	test::jail_t jail;
	for(auto const& file : { "page.html", "page.htm", "image.png", "image.svg", "paper.pdf" })
	{
		jail.touch(file);
		OAK_ASSERT_EQ(action_for(link_to(jail, file), YES), "load");
	}
}

void test_other_files_open_in_textmate ()
{
	test::jail_t jail;
	for(auto const& file : { "notes.md", "notes.txt", "script.rb", "style.css", "data.json", "README" })
	{
		jail.touch(file);
		OAK_ASSERT_EQ(action_for(link_to(jail, file), YES), "open");
	}
}

void test_directories_and_missing_files_load_in_the_web_view ()
{
	test::jail_t jail;
	jail.mkdir("docs");

	OAK_ASSERT_EQ(action_for(link_to(jail, "docs"), YES), "load");
	OAK_ASSERT_EQ(action_for(link_to(jail, "missing.md"), YES), "load");
}

void test_fragment_of_the_document_scrolls_in_place ()
{
	test::jail_t jail;
	jail.touch("notes.md");
	jail.touch("other.md");
	NSString* document = [NSString stringWithUTF8String:jail.path("notes.md").c_str()];

	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md", @"terms"), YES, document), "scroll");
	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md"), YES, document), "open");
	OAK_ASSERT_EQ(action_for(link_to(jail, "other.md", @"terms"), YES, document), "open");
	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md", @"terms"), YES), "open");
}

void test_file_scheme_is_treated_like_tm_file ()
{
	test::jail_t jail;
	jail.touch("notes.md");

	OAK_ASSERT_EQ(action_for(link_to(jail, "notes.md", nil, @"file"), YES), "open");
}

void test_remote_urls_are_left_alone ()
{
	OAK_ASSERT_EQ(action_for([NSURL URLWithString:@"https://example.com/notes.md"], YES), "load");
}

void test_txmt_open_url_survives_the_query_parser ()
{
	NSURL* url = OakTxMtOpenURLForPath(@"/tmp/a b&c=d.md");
	OAK_ASSERT_EQ(std::string(url.absoluteString.UTF8String), "txmt://open?url=file:///tmp/a%20b%26c%3Dd.md");

	// handleTxMtURL: splits the query on & and =, then percent-decodes each value.
	std::string query = url.query.UTF8String;
	OAK_ASSERT(query.find('&') == std::string::npos);
	OAK_ASSERT_EQ(decode::url_part(query.substr(strlen("url="))), "file:///tmp/a b&c=d.md");
}

void test_scroll_script_quotes_the_fragment ()
{
	OAK_ASSERT_EQ(std::string(OakScrollToFragmentScript(@"terms").UTF8String), "location.hash = \"terms\"");
	OAK_ASSERT_EQ(std::string(OakScrollToFragmentScript(@"a\"b\\c").UTF8String), "location.hash = \"a\\\"b\\\\c\"");
}
