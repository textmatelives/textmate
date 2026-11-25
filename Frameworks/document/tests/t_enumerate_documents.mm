#import "../src/OakDocument.h"
#import "../src/OakDocumentController.h"
#import <test/jail.h>
#include <unistd.h>

// enumerateDocumentsAtPaths: top-level symbolic links must be drained even
// when no directories were passed (they used to be dropped silently when
// dirs stayed empty). Explicit regular files intentionally bypass glob
// filtering (“search what I selected”).

static NSString* JailPath (test::jail_t const& jail, char const* relative)
{
	return [NSString stringWithUTF8String:jail.path(relative).c_str()];
}

static void MakeSymlink (NSString* target, NSString* link)
{
	OAK_ASSERT(::symlink(target.fileSystemRepresentation, link.fileSystemRepresentation) == 0);
}

static NSArray<NSString*>* Enumerate (NSArray* items, NSDictionary* options)
{
	NSMutableArray<NSString*>* paths = [NSMutableArray array];
	[OakDocumentController.sharedInstance enumerateDocumentsAtPaths:items options:options usingBlock:^(OakDocument* document, BOOL* stop){
		[paths addObject:document.path];
	}];
	return paths;
}

void test_symlink_to_file_without_directories_is_enumerated ()
{
	test::jail_t jail;
	jail.set_content("real.txt", "hello");
	NSString* target = JailPath(jail, "real.txt");
	NSString* link = JailPath(jail, "link.txt");
	MakeSymlink(target, link);

	NSArray<NSString*>* paths = Enumerate(@[ link ], @{});
	OAK_ASSERT_EQ(paths.count, 1u);
	OAK_ASSERT([paths.firstObject isEqual:target]);
}

void test_symlink_to_directory_without_directories_is_enumerated ()
{
	test::jail_t jail;
	jail.set_content("docs/note.txt", "hello");
	NSString* link = JailPath(jail, "linkdir");
	MakeSymlink(JailPath(jail, "docs"), link);

	NSArray<NSString*>* paths = Enumerate(@[ link ], @{ kSearchFollowDirectoryLinksKey: @YES });
	OAK_ASSERT_EQ(paths.count, 1u);
	OAK_ASSERT([paths.firstObject isEqual:JailPath(jail, "docs/note.txt")]);
}

void test_explicit_file_ignores_non_matching_glob ()
{
	test::jail_t jail;
	jail.set_content("note.txt", "hello");
	NSString* file = JailPath(jail, "note.txt");

	NSArray<NSString*>* paths = Enumerate(@[ file ], @{ kSearchFileGlobsKey: @[ @"*.nomatch" ] });
	OAK_ASSERT_EQ(paths.count, 1u);
	OAK_ASSERT([paths.firstObject isEqual:file]);
}

void test_mixed_directory_and_symlink_enumerates_both ()
{
	test::jail_t jail;
	jail.set_content("dir/a.txt", "a");
	jail.set_content("b.txt", "b");
	MakeSymlink(JailPath(jail, "b.txt"), JailPath(jail, "link.txt"));

	NSArray<NSString*>* paths = Enumerate(@[ JailPath(jail, "dir"), JailPath(jail, "link.txt") ], @{});
	OAK_ASSERT_EQ(paths.count, 2u);
	OAK_ASSERT([paths containsObject:JailPath(jail, "dir/a.txt")]);
	OAK_ASSERT([paths containsObject:JailPath(jail, "b.txt")]);
}
