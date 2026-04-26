#include <scm/scm.h>
#include <io/exec.h>
#include <text/format.h>
#include <test/jail.h>

void test_disabling_scm ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "scmStatus = false\n");
	OAK_ASSERT_EQ(scm::info(jail.path()) ? true : false, false);
}

// Each shared_info_t owns its own dispatch queue (was a function-local
// static — one queue serialized every repo). This test confirms that
// two info_t instances for different paths produce independent status
// without one's lifetime affecting the other's.
void test_two_repos_have_independent_queues ()
{
	static std::string const git = scm::find_executable("git", "TM_GIT");
	if(git == NULL_STR)
		return;

	auto bootstrap = [&](test::jail_t const& jail) {
		std::string script = text::format(
			"{ cd '%1$s' && '%2$s' init -b master "
			"&& '%2$s' config user.email 'test@example.com' "
			"&& '%2$s' config user.name 'Test Test' "
			"&& '%2$s' config commit.gpgsign false "
			"&& touch .dummy && '%2$s' add .dummy "
			"&& '%2$s' commit .dummy -mGetHead ; } >/dev/null",
			jail.path().c_str(), git.c_str());
		io::exec("/bin/sh", "-c", script.c_str(), nullptr);
	};

	test::jail_t jail_a, jail_b;
	bootstrap(jail_a);
	bootstrap(jail_b);

	auto info_a = scm::info(jail_a.path());
	auto info_b = scm::info(jail_b.path());

	OAK_ASSERT(info_a);
	OAK_ASSERT(info_b);

	scm::wait_for_status(info_a);
	scm::wait_for_status(info_b);

	OAK_ASSERT_EQ(info_a->scm_variables()["TM_SCM_NAME"], "git");
	OAK_ASSERT_EQ(info_b->scm_variables()["TM_SCM_NAME"], "git");
	OAK_ASSERT_NE(info_a->root_path(), info_b->root_path());

	// Tearing down info_a (and its shared_info_t with its queue) must
	// not leave info_b in a bad state.
	info_a.reset();
	OAK_ASSERT_EQ(info_b->scm_variables()["TM_SCM_NAME"], "git");
}
