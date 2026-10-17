#import <test/jail.h>
#import <quicklook/quicklook.h>
#import <ns/ns.h>

static std::string const TestGrammar =
	"{ fileTypes = ( qltest );\n"
	"  name = 'QuickLook Test';\n"
	"  scopeName = 'source.qltest';\n"
	"  uuid = 'AAAAAAAA-1111-2222-3333-444444444444';\n"
	"  patterns = ( { match = 'hello'; name = 'keyword.qltest'; } );\n"
	"}\n";

static std::string const TestTheme =
	"{ name = 'QuickLook Test';\n"
	"  uuid = 'BBBBBBBB-1111-2222-3333-444444444444';\n"
	"  settings = (\n"
	"    { settings = { foreground = '#000000'; background = '#FFFFFF'; }; },\n"
	"    { scope = 'keyword'; settings = { foreground = '#FF0000'; }; },\n"
	"  );\n"
	"}\n";

static std::string const TestThemeUUID = "BBBBBBBB-1111-2222-3333-444444444444";

static test::jail_t& shared_jail ()
{
	static test::jail_t jail;
	return jail;
}

void setup_fixtures ()
{
	test::jail_t& jail = shared_jail();
	jail.set_content("Bundles/QLTest.tmbundle/info.plist", "{ name = 'QuickLook Test'; uuid = 'CCCCCCCC-1111-2222-3333-444444444444'; }");
	jail.set_content("Bundles/QLTest.tmbundle/Syntaxes/Test.tmLanguage", TestGrammar);
	jail.set_content("Bundles/QLTest.tmbundle/Themes/Test.tmTheme", TestTheme);
	quicklook::setup(jail.path("Bundles"));
}

static NSColor* fg_at (NSAttributedString* str, NSUInteger i)
{
	return [str attributesAtIndex:i effectiveRange:NULL][NSForegroundColorAttributeName];
}

static bool is_pure (NSColor* color, CGFloat r, CGFloat g, CGFloat b)
{
	return color && fabs(color.redComponent - r) < 0.01 && fabs(color.greenComponent - g) < 0.01 && fabs(color.blueComponent - b) < 0.01;
}

void test_render_applies_grammar_and_theme ()
{
	test::jail_t& jail = shared_jail();
	jail.set_content("hello.qltest", "hello world");

	std::string fileType;
	NSAttributedString* str = quicklook::render_file(jail.path("hello.qltest"), TestThemeUUID, "Menlo", 12, 20480, SIZE_T_MAX, &fileType);
	OAK_ASSERT(str != nil);
	OAK_ASSERT(fileType == "source.qltest");
	OAK_ASSERT(to_s([str string]) == "hello world");

	OAK_ASSERT(is_pure(fg_at(str, 0), 1, 0, 0));
	OAK_ASSERT(is_pure(fg_at(str, 6), 0, 0, 0));
}

void test_render_truncates_lines ()
{
	test::jail_t& jail = shared_jail();
	jail.set_content("multi.qltest", "one\ntwo\nthree\n");

	NSAttributedString* str = quicklook::render_file(jail.path("multi.qltest"), TestThemeUUID, "Menlo", 12, 20480, 2);
	OAK_ASSERT(str != nil);
	OAK_ASSERT(to_s([str string]) == "one\ntwo");
}

void test_render_empty_file_returns_empty_string ()
{
	test::jail_t& jail = shared_jail();
	jail.set_content("empty.qltest", "");

	NSAttributedString* str = quicklook::render_file(jail.path("empty.qltest"), TestThemeUUID, "Menlo", 12);
	OAK_ASSERT(str != nil);
	OAK_ASSERT([str length] == 0);
}

void test_render_reports_unknown_type ()
{
	test::jail_t& jail = shared_jail();
	jail.set_content("mystery.zzzunknown", "???");

	std::string fileType = "sentinel";
	quicklook::render_file(jail.path("mystery.zzzunknown"), TestThemeUUID, "Menlo", 12, 20480, SIZE_T_MAX, &fileType);
	OAK_ASSERT(fileType == NULL_STR);
}
