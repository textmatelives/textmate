#include <plist/schema.h>

// A plist reaching a schema is arbitrary user data: nothing has validated that
// each key holds the type the schema maps it to. Grammars and themes in the
// wild do carry a numeric `name` or a string `disabled`, and TextMate has
// always coerced those rather than rejecting the whole file.
//
// The coercion lives in plist::convert<T>. Reading the value with
// plist::get<T> instead throws std::bad_variant_access, which in a release
// build escapes NSApplicationMain and aborts the application as it opens a
// document. These fixtures build the mismatched types directly, because the
// ASCII plist parser reads every unquoted token as a string and so cannot
// produce them; the real ones arrive from XML and binary plists via
// CFPropertyList.

struct record_t
{
	std::string name;
	std::string content;
	int32_t disabled = -1;
	bool flag = false;
};

static plist::schema_t<record_t> const& record_schema ()
{
	static plist::schema_t<record_t> schema = plist::schema_t<record_t>()
		.map("name",     &record_t::name)
		.map("content",  &record_t::content)
		.map("disabled", &record_t::disabled)
		.map("flag",     &record_t::flag)
	;
	return schema;
}

void test_schema_reads_matching_types ()
{
	plist::dictionary_t dict;
	dict["name"]     = std::string("example");
	dict["disabled"] = int32_t(1);
	dict["flag"]     = true;

	record_t rec;
	OAK_ASSERT(record_schema().convert(dict, &rec));
	OAK_ASSERT_EQ(rec.name, "example");
	OAK_ASSERT_EQ(rec.disabled, 1);
	OAK_ASSERT_EQ(rec.flag, true);
}

void test_schema_coerces_mismatched_types ()
{
	plist::dictionary_t dict;
	dict["name"]     = int32_t(42);            // schema wants a string
	dict["content"]  = true;                   // schema wants a string
	dict["disabled"] = std::string("no");      // schema wants an int32_t

	record_t rec;
	OAK_ASSERT(record_schema().convert(dict, &rec));
	OAK_ASSERT_EQ(rec.disabled, 0);
}

void test_schema_coerces_container_mismatch ()
{
	// A container where a scalar is expected has no sensible coercion, so the
	// field is left default-constructed. It must still not throw.
	plist::dictionary_t dict;
	dict["name"] = plist::array_t{ plist::any_t(std::string("a")) };

	record_t rec;
	rec.name = "untouched";
	OAK_ASSERT(record_schema().convert(dict, &rec));
	OAK_ASSERT_EQ(rec.name, "");
}
