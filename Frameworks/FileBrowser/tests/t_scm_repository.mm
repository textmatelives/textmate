#import "../src/SCMManager.h"
#import <io/exec.h>
#import <io/path.h>
#import <text/format.h>
#import <scm/scm.h>
#import <test/jail.h>

// Smoke test confirming SCMRepository wires through scm::info_t and
// reports a useful status map after wait_for_status returns. Before
// workstream C the class ran its own driver->status() / variables() on
// the global concurrent queue, duplicating the C++ shared_info_t work;
// now it observes the C++ system via push_callback.
//
// Skipped when `git` is not at /usr/bin/git (matches the contract used
// by t_git.cc / t_scm.cc, which similarly fail-soft when an SCM driver
// binary is absent).

void test_scm_repository_observes_cxx_info ()
{
	std::string const git = "/usr/bin/git";
	if(!path::is_executable(git))
		return;

	test::jail_t jail;
	std::string script = text::format(
		"{ cd '%1$s' && '%2$s' init -b master "
		"&& '%2$s' config user.email 'test@example.com' "
		"&& '%2$s' config user.name 'Test Test' "
		"&& '%2$s' config commit.gpgsign false "
		"&& touch tracked && '%2$s' add tracked "
		"&& '%2$s' commit tracked -mInitial "
		"&& touch untracked ; } >/dev/null",
		jail.path().c_str(), git.c_str());
	io::exec("/bin/sh", "-c", script.c_str(), nullptr);

	// Pump the run loop until the C++ scm::info_t has populated. We use
	// scm::wait_for_status to synchronise; the SCMRepository observes the
	// same info_t and will have its callback fired in the meantime.
	scm::info_ptr info = scm::info(jail.path());
	OAK_ASSERT(info);
	scm::wait_for_status(info);

	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:jail.path().c_str()] isDirectory:YES];
	SCMRepository* repository = [SCMManager.sharedInstance repositoryAtURL:url];

	OAK_ASSERT(repository);
	OAK_ASSERT_EQ(repository.enabled, YES);
	OAK_ASSERT_EQ(repository.hasStatus, YES);
	OAK_ASSERT_EQ(repository.variables[@"TM_SCM_NAME"].UTF8String, std::string("git"));

	// The untracked file should show up in repository.status with
	// scm::status::unversioned. Capture the map locally so .find() does
	// not iterate a property accessor's temporary copy.
	std::map<std::string, scm::status::type> const status = repository.status;
	std::string untrackedPath = jail.path() + "/untracked";
	auto it = status.find(untrackedPath);
	OAK_ASSERT(it != status.end());
	OAK_ASSERT_EQ(it->second, scm::status::unversioned);
}
