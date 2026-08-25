#include <io/environment.h>
#include <io/exec.h>

// A GUI app launched from Finder inherits no locale at all — the running
// TextMate has only __CF_USER_TEXT_ENCODING, no LANG and no LC_*. Ruby then
// reports Encoding.default_external as US-ASCII, so bundle commands read stdin
// and files as bytes and tag ENV strings ASCII-8BIT. Interpolating a
// TM_FILEPATH containing an accent into a UTF-8 literal raises
// Encoding::CompatibilityError.
//
// bash_init.sh has always exported LC_CTYPE, but fix_shebang only prepends it
// for commands with no shebang of their own, so every "#!/usr/bin/env ruby"
// command missed out. Setting it here covers all of them.
void test_environment_sets_lc_ctype ()
{
	auto const& env = oak::basic_environment();
	auto it = env.find("LC_CTYPE");
	OAK_ASSERT(it != env.end());
	OAK_ASSERT_EQ(it->second, "UTF-8");
}

// Guard the rest of setup_basic_environment() against collateral damage.
void test_environment_keeps_basic_keys ()
{
	auto const& env = oak::basic_environment();
	for(char const* key : { "HOME", "PATH", "TMPDIR", "LOGNAME", "USER" })
		OAK_ASSERT(env.find(key) != env.end());
}

// The map is only half of it — prove a spawned child actually receives the
// variable, and that Ruby, which is what most bundle commands are written in,
// resolves it to UTF-8 rather than falling back to US-ASCII.
//
// The equivalent end-to-end test belongs in the command suite, but that one is
// excluded from CI: wait_for_command() polls NSApp, which is nil in a CLI test
// binary, so it hangs. io::exec goes through the same oak::basic_environment().
void test_environment_reaches_spawned_process ()
{
	OAK_ASSERT_EQ(io::exec("/bin/sh", "-c", "printf %s \"$LC_CTYPE\"", nullptr), "UTF-8");
	OAK_ASSERT_EQ(io::exec("/usr/bin/ruby", "-e", "print Encoding.default_external", nullptr), "UTF-8");
}
