#import <encoding/encoding.h>

void test_detect_utf8_multibyte ()
{
	std::string s = "caf\xC3\xA9";
	OAK_ASSERT_EQ(encoding::detect(s.data(), s.data() + s.size()), "UTF-8");
}

void test_detect_latin1 ()
{
	// "café" with é encoded as 0xE9 — valid in ISO-8859-1 / WINDOWS-1252 and
	// invalid as standalone UTF-8.
	std::string s = "caf\xE9";
	std::string result = encoding::detect(s.data(), s.data() + s.size());
	OAK_ASSERT_EQ(result, "WINDOWS-1252");
}

void test_detect_shift_jis ()
{
	// "こんにちは" encoded in Shift-JIS. Foundation labels Shift-JIS data with
	// the IANA name "CP932" (Microsoft code page 932), not "SHIFT_JIS".
	std::string s = "\x82\xB1\x82\xF1\x82\xC9\x82\xBF\x82\xCD";
	std::string result = encoding::detect(s.data(), s.data() + s.size());
	OAK_ASSERT_EQ(result, "CP932");
}

void test_detect_empty_buffer ()
{
	// An empty buffer is treated as UTF-8 (the universal default). Foundation
	// would return 0 for empty data; encoding::detect short-circuits this case.
	char const* p = nullptr;
	OAK_ASSERT_EQ(encoding::detect(p, p), "UTF-8");
}

void test_detect_pure_ascii ()
{
	// Pure 7-bit ASCII is a strict UTF-8 subset, but Foundation labels it
	// with the most specific IANA name it can: "US-ASCII".
	std::string s = "Hello, world.";
	OAK_ASSERT_EQ(encoding::detect(s.data(), s.data() + s.size()), "US-ASCII");
}

void test_charsets_includes_utf8 ()
{
	auto cs = encoding::charsets();
	OAK_ASSERT(std::find(cs.begin(), cs.end(), "UTF-8") != cs.end());
}
