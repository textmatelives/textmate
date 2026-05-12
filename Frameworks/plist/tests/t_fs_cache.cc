#include <plist/fs_cache.h>
#include <test/jail.h>

// Round-trip tests for plist::cache_t serialization. The public API surface
// being exercised is cache_t::save(path) and cache_t::load(path). Tests are
// format-agnostic and should pass against any serialization implementation
// that preserves the entries.

static std::string const kTestCachePath = "BundlesIndex.binary";

void test_empty_cache_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	plist::cache_t a;
	a.save(path);

	plist::cache_t b;
	b.load(path);

	OAK_ASSERT_EQ(b.entries("/nonexistent").size(), 0);
}

void test_single_file_entry_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	jail.set_content("file.plist", "{}");
	std::string filePath = jail.path("file.plist");

	plist::cache_t a;
	plist::dictionary_t fetched = a.content(filePath);
	// After the synthetic load, the cache holds an entry for filePath.
	a.save(path);

	plist::cache_t b;
	b.load(path);
	plist::dictionary_t roundtripped = b.content(filePath);
	OAK_ASSERT_EQ(roundtripped.size(), fetched.size());
}

void test_file_entry_with_content_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	// Write a real plist file. cache_t::content() parses and caches it.
	jail.set_content("file.plist", "{ uuid = 'ABCD-1234'; name = 'Example'; scope = 'source.example'; }");
	std::string filePath = jail.path("file.plist");

	plist::cache_t a;
	plist::dictionary_t original = a.content(filePath);
	OAK_ASSERT(original.find("uuid") != original.end());
	a.save(path);

	plist::cache_t b;
	b.load(path);
	plist::dictionary_t roundtripped = b.content(filePath);
	OAK_ASSERT_EQ(roundtripped.size(), original.size());
	OAK_ASSERT_EQ(boost::get<std::string>(roundtripped["uuid"]), "ABCD-1234");
	OAK_ASSERT_EQ(boost::get<std::string>(roundtripped["name"]), "Example");
}

void test_directory_entry_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	jail.set_content("dir/a.plist", "{}");
	jail.set_content("dir/b.plist", "{}");
	std::string dirPath = jail.path("dir");

	plist::cache_t a;
	auto entriesA = a.entries(dirPath);
	OAK_ASSERT_EQ(entriesA.size(), 2);
	a.save(path);

	plist::cache_t b;
	b.load(path);
	auto entriesB = b.entries(dirPath);
	OAK_ASSERT_EQ(entriesB.size(), 2);
	OAK_ASSERT_EQ(entriesB, entriesA);
}

void test_link_entry_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	jail.set_content("target.plist", "{ uuid = 'XYZ'; }");
	jail.ln("link.plist", "target.plist");
	std::string linkPath = jail.path("link.plist");

	plist::cache_t a;
	plist::dictionary_t original = a.content(linkPath);
	OAK_ASSERT(original.find("uuid") != original.end());
	a.save(path);

	plist::cache_t b;
	b.load(path);
	plist::dictionary_t roundtripped = b.content(linkPath);
	OAK_ASSERT_EQ(boost::get<std::string>(roundtripped["uuid"]), "XYZ");
}

void test_missing_entry_roundtrip ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	std::string ghostPath = jail.path("does_not_exist.plist");

	plist::cache_t a;
	a.content(ghostPath); // Creates a missing entry as a side-effect.
	a.save(path);

	plist::cache_t b;
	b.load(path);
	// Missing entries should survive the round-trip without crashing.
	plist::dictionary_t res = b.content(ghostPath);
	OAK_ASSERT_EQ(res.size(), 0);
}

void test_event_id_preserved ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	jail.set_content("dir/a.plist", "{}");
	std::string dirPath = jail.path("dir");

	plist::cache_t a;
	a.entries(dirPath);
	// Use a 64-bit value that exceeds INT32_MAX so the type round-trips as
	// uint64_t and not int32_t — matching how FSEvents emits real event ids.
	uint64_t const expected = uint64_t(0x100000000ULL) + uint64_t(42);
	a.set_event_id_for_path(expected, dirPath);
	a.save(path);

	plist::cache_t b;
	b.load(path);
	OAK_ASSERT_EQ(b.event_id_for_path(dirPath), expected);
}

void test_version_mismatch_rejected ()
{
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	// Write garbage to the cache path.
	jail.set_content(kTestCachePath, "this is not a valid cache file");

	plist::cache_t b;
	b.load(path); // Must not crash.

	// Behaviour: cache stays empty; subsequent content() returns a missing entry.
	plist::dictionary_t res = b.content(jail.path("nope.plist"));
	OAK_ASSERT_EQ(res.size(), 0);
}

void test_old_capnp_file_silently_ignored ()
{
	// A leftover capnp-format file at the cache path must not crash the new
	// loader. The capnp file format starts with a small fixed header; an
	// arbitrary binary blob is sufficient to exercise the failure path.
	test::jail_t jail;
	std::string path = jail.path(kTestCachePath);

	// Bytes that resemble the start of a packed capnp message but are not a
	// valid NSKeyedArchiver / property-list archive.
	std::string capnpBytes;
	capnpBytes.append("\x10\x00\x00\x00", 4);
	capnpBytes.append("\x00\x00\x00\x00", 4);
	capnpBytes.append("garbage payload", 15);
	jail.set_content(kTestCachePath, capnpBytes);

	plist::cache_t b;
	b.load(path); // Must not throw, must not crash.

	plist::dictionary_t res = b.content(jail.path("nope.plist"));
	OAK_ASSERT_EQ(res.size(), 0);
}
