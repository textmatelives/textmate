#include "../src/drivers/git_parse.h"
#include <oak/debug.h>

// =====================
// = resolve_porcelain_xy =
// =====================

void test_resolve_xy_clean ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy(' ', ' '), scm::status::none);
}

void test_resolve_xy_modified_unstaged ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy(' ', 'M'), scm::status::modified);
}

void test_resolve_xy_modified_staged ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('M', ' '), scm::status::modified);
}

void test_resolve_xy_modified_both ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('M', 'M'), scm::status::modified);
}

void test_resolve_xy_added_staged ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('A', ' '), scm::status::added);
}

void test_resolve_xy_added_then_modified ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('A', 'M'), scm::status::added);
}

void test_resolve_xy_deleted_unstaged ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy(' ', 'D'), scm::status::deleted);
}

void test_resolve_xy_deleted_staged ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('D', ' '), scm::status::deleted);
}

void test_resolve_xy_renamed ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('R', ' '), scm::status::added);
}

void test_resolve_xy_copied ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('C', ' '), scm::status::added);
}

void test_resolve_xy_type_change ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy(' ', 'T'), scm::status::modified);
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('T', ' '), scm::status::modified);
}

void test_resolve_xy_untracked ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('?', '?'), scm::status::unversioned);
}

void test_resolve_xy_ignored ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('!', '!'), scm::status::ignored);
}

void test_resolve_xy_conflict_uu ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('U', 'U'), scm::status::conflicted);
}

void test_resolve_xy_conflict_aa ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('A', 'A'), scm::status::conflicted);
}

void test_resolve_xy_conflict_dd ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('D', 'D'), scm::status::conflicted);
}

void test_resolve_xy_conflict_au ()
{
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('A', 'U'), scm::status::conflicted);
	OAK_ASSERT_EQ(scm::git_parse::resolve_porcelain_xy('U', 'A'), scm::status::conflicted);
}

// ===================
// = parse_porcelain =
// ===================

void test_parse_porcelain_empty ()
{
	std::map<std::string, scm::status::type> entries;
	scm::git_parse::parse_porcelain(entries, "");
	OAK_ASSERT_EQ(entries.size(), 0);
}

void test_parse_porcelain_null ()
{
	std::map<std::string, scm::status::type> entries;
	scm::git_parse::parse_porcelain(entries, NULL_STR);
	OAK_ASSERT_EQ(entries.size(), 0);
}

void test_parse_porcelain_modified_unstaged ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string(" M foo.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries.size(), 1);
	OAK_ASSERT_EQ(entries["foo.txt"], scm::status::modified);
}

void test_parse_porcelain_added_staged ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string("A  newfile.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["newfile.txt"], scm::status::added);
}

void test_parse_porcelain_untracked ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string("?? new.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["new.txt"], scm::status::unversioned);
}

void test_parse_porcelain_ignored ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string("!! ignored.tmp") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["ignored.tmp"], scm::status::ignored);
}

void test_parse_porcelain_conflict ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string("UU conflict.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["conflict.txt"], scm::status::conflicted);
}

void test_parse_porcelain_rename_becomes_add_plus_delete ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string("R  newpath.txt") + '\0' + "oldpath.txt" + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries.size(), 2);
	OAK_ASSERT_EQ(entries["newpath.txt"], scm::status::added);
	OAK_ASSERT_EQ(entries["oldpath.txt"], scm::status::deleted);
}

void test_parse_porcelain_multiple_entries ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output =
		std::string(" M a.txt") + '\0' +
		"A  b.txt" + '\0' +
		"?? c.txt" + '\0' +
		" D d.txt" + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries.size(), 4);
	OAK_ASSERT_EQ(entries["a.txt"], scm::status::modified);
	OAK_ASSERT_EQ(entries["b.txt"], scm::status::added);
	OAK_ASSERT_EQ(entries["c.txt"], scm::status::unversioned);
	OAK_ASSERT_EQ(entries["d.txt"], scm::status::deleted);
}

void test_parse_porcelain_overlay ()
{
	// Existing baseline (from ls-files -zt) marks file as tracked-clean;
	// porcelain overlays modified status.
	std::map<std::string, scm::status::type> entries;
	entries["foo.txt"] = scm::status::none;
	std::string output = std::string(" M foo.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["foo.txt"], scm::status::modified);
}

void test_parse_porcelain_path_with_space ()
{
	std::map<std::string, scm::status::type> entries;
	std::string output = std::string(" M dir with space/file.txt") + '\0';
	scm::git_parse::parse_porcelain(entries, output);
	OAK_ASSERT_EQ(entries["dir with space/file.txt"], scm::status::modified);
}
