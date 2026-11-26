#import <Find/Find.h>

// The glob box is only meaningful for folder scopes. Explicit file lists
// (Open Files, Recent Files) bypass glob filtering, as do the
// single-document scopes, so the box is disabled for all of them.

// These tests use a fresh Find instance rather than the shared one:
// t_window_height requires the shared window to load fresh (it observes
// frame-autosave + snap-to-content at load time).
static Find* NewFind ()
{
	return [[Find alloc] init];
}

// canEditGlob lives in Find.mm’s class extension; the generated runner wraps
// this file in a namespace, so reach it via KVC rather than @interface.
static BOOL CanEditGlob (Find* find)
{
	return [[find valueForKey:@"canEditGlob"] boolValue];
}

void test_glob_box_enabled_only_for_folder_scopes ()
{
	Find* find = NewFind();

	find.searchTarget = FFSearchTargetDocument;
	OAK_ASSERT(CanEditGlob(find) == NO);

	find.searchTarget = FFSearchTargetSelection;
	OAK_ASSERT(CanEditGlob(find) == NO);

	find.searchTarget = FFSearchTargetOpenFiles;
	OAK_ASSERT(CanEditGlob(find) == NO);

	find.searchTarget = FFSearchTargetRecentFiles;
	OAK_ASSERT(CanEditGlob(find) == NO);

	find.searchTarget = FFSearchTargetProject;
	OAK_ASSERT(CanEditGlob(find) == YES);

	find.searchTarget = FFSearchTargetFileBrowserItems;
	OAK_ASSERT(CanEditGlob(find) == YES);

	find.searchTarget = FFSearchTargetOther;
	OAK_ASSERT(CanEditGlob(find) == YES);
}

void test_recent_files_window_title ()
{
	Find* find = NewFind();
	find.searchTarget = FFSearchTargetRecentFiles;
	OAK_ASSERT([find.window.title isEqualToString:@"Find — Recent Files"]);
}
