#import "../src/OakDocument.h"
#import "../src/OakDocumentController.h"
#import <test/jail.h>
#include <unistd.h>

// recentClosedFilePaths: recency-ordered LRU paths, skipping open documents
// and files that no longer exist. Assertions are relative to each test’s own
// jail since ranks accumulate on the shared controller across tests.

static NSString* JailPath (test::jail_t const& jail, char const* relative)
{
	return [NSString stringWithUTF8String:jail.path(relative).c_str()];
}

static OakDocument* Touch (NSString* path)
{
	OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:path];
	[OakDocumentController.sharedInstance didTouchDocument:doc];
	return doc;
}

static NSArray<NSString*>* Recents ()
{
	return [OakDocumentController.sharedInstance recentClosedFilePaths];
}

void test_recent_paths_are_ordered_by_touch ()
{
	test::jail_t jail;
	jail.set_content("a.txt", "a");
	jail.set_content("b.txt", "b");
	NSString* a = JailPath(jail, "a.txt");
	NSString* b = JailPath(jail, "b.txt");
	Touch(a);
	Touch(b);

	NSArray<NSString*>* recents = Recents();
	OAK_ASSERT([recents containsObject:a]);
	OAK_ASSERT([recents containsObject:b]);
	OAK_ASSERT_LT([recents indexOfObject:b], [recents indexOfObject:a]);
}

void test_recent_paths_skip_open_documents ()
{
	test::jail_t jail;
	jail.set_content("open.txt", "x");
	NSString* path = JailPath(jail, "open.txt");
	OakDocument* doc = Touch(path);

	[doc open];
	OAK_ASSERT(![Recents() containsObject:path]);
	[doc close];
	OAK_ASSERT([Recents() containsObject:path]);
}

void test_recent_paths_skip_missing_files ()
{
	test::jail_t jail;
	NSString* path = JailPath(jail, "gone.txt");
	Touch(path); // never created on disk
	OAK_ASSERT(![Recents() containsObject:path]);
}

void test_recent_paths_include_symlink_to_file ()
{
	test::jail_t jail;
	jail.set_content("real.txt", "x");
	NSString* link = JailPath(jail, "link.txt");
	OAK_ASSERT(::symlink(JailPath(jail, "real.txt").fileSystemRepresentation, link.fileSystemRepresentation) == 0);
	Touch(link);
	OAK_ASSERT([Recents() containsObject:link]);
}
