#include "../src/fs_events.h"

void test_keeps_paths_outside_dotgit ()
{
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/src/main.cc"),       false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/README.md"),         false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/subdir/file.lock"),  false);
}

void test_keeps_real_dotgit_files ()
{
	// Real index/HEAD/refs writes should propagate; only lockfiles and
	// fsmonitor IPC are filtered.
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/HEAD"),                  false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/index"),                 false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/packed-refs"),           false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/refs/heads/main"),       false);
}

void test_filters_lockfiles ()
{
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/index.lock"),            true);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/HEAD.lock"),             true);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/refs/heads/main.lock"),  true);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/packed-refs.lock"),      true);
}

void test_filters_fsmonitor_ipc ()
{
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/fsmonitor--daemon.ipc"),       true);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/fsmonitor--daemon.sock"),      true);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/.git/fsmonitor--daemon.token"),     true);
}

void test_does_not_match_lock_outside_dotgit ()
{
	// A user file named `*.lock` outside .git/ is a real edit, not noise.
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/Cargo.lock"),                 false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/yarn.lock"),                  false);
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/Pipfile.lock"),               false);
}

void test_does_not_match_fsmonitor_outside_dotgit ()
{
	// Defensively make sure prefix match is anchored after `/.git/`.
	OAK_ASSERT_EQ(scm::is_transient_git_path("/repo/fsmonitor--daemon.ipc"),      false);
}
