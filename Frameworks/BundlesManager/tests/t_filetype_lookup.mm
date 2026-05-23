#import "../src/BundleRegistry.h"
#import "../src/BundleSpec.h"
#import <test/jail.h>

// Phase 1: BundleRegistry.bundleSpecForFileExtension: lookup.
//
// The index ships inside Bundle Support.tmbundle/Support/BundleFileTypeIndex.plist
// (managed install preferred; embedded copy under <App>/Contents/SharedSupport
// is the fallback). Tests synthesise small index files in a jail directory
// and exercise the loader + lookup through a non-singleton init seam.

static NSString* const kPythonUUID = @"E12C1C8B-25B0-4A28-9E9D-1D2C9E5C49A5";
static NSString* const kRubyUUID   = @"467B298F-6227-11D9-BFB1-000D93589AF6";
static NSString* const kGhostUUID  = @"00000000-0000-0000-0000-000000000099";

static NSString* WriteIndex (test::jail_t const& jail, NSDictionary* byExtension)
{
	NSDictionary* root = @{
		@"version":     @1,
		@"byExtension": byExtension,
	};
	NSString* path = [NSString stringWithUTF8String:jail.path("BundleFileTypeIndex.plist").c_str()];
	[root writeToFile:path atomically:YES];
	return path;
}

static BundleSpec* MakeSpec (NSString* uuidStr, NSString* name)
{
	NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
	return [[BundleSpec alloc] initWithUUID:uuid name:name url:@"https://example.invalid/x.tmbundle" ref:@"main"];
}

// ---------------------------------------------------------------------------
// Loader: + loadFileTypeIndexFromPath:
// ---------------------------------------------------------------------------

void test_loader_returns_ext_to_uuid_map ()
{
	test::jail_t jail;
	NSString* path = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
		@"rb": @{ @"bundleUUID": kRubyUUID,   @"bundleName": @"Ruby"   },
	});

	NSDictionary<NSString*, NSUUID*>* map = [BundleRegistry loadFileTypeIndexFromPath:path];
	OAK_ASSERT(map != nil);
	OAK_ASSERT_EQ(map.count, 2u);
	OAK_ASSERT([map[@"py"] isEqual:[[NSUUID alloc] initWithUUIDString:kPythonUUID]]);
	OAK_ASSERT([map[@"rb"] isEqual:[[NSUUID alloc] initWithUUIDString:kRubyUUID]]);
}

void test_loader_returns_empty_dict_for_missing_file ()
{
	test::jail_t jail;
	NSString* path = [NSString stringWithUTF8String:jail.path("nonexistent.plist").c_str()];

	NSDictionary<NSString*, NSUUID*>* map = [BundleRegistry loadFileTypeIndexFromPath:path];
	OAK_ASSERT(map != nil);
	OAK_ASSERT_EQ(map.count, 0u);
}

void test_loader_skips_entries_with_invalid_uuid ()
{
	test::jail_t jail;
	NSString* path = WriteIndex(jail, @{
		@"py":  @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
		@"bad": @{ @"bundleUUID": @"not-a-uuid", @"bundleName": @"Garbage" },
	});

	NSDictionary<NSString*, NSUUID*>* map = [BundleRegistry loadFileTypeIndexFromPath:path];
	OAK_ASSERT_EQ(map.count, 1u);
	OAK_ASSERT(map[@"py"] != nil);
	OAK_ASSERT(map[@"bad"] == nil);
}

// ---------------------------------------------------------------------------
// Accessor: -bundleSpecForFileExtension:
// ---------------------------------------------------------------------------

void test_known_ext_not_installed_returns_spec ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	BundleSpec* hit = [reg bundleSpecForFileExtension:@"py"];
	OAK_ASSERT(hit != nil);
	OAK_ASSERT([hit.uuid isEqual:python.uuid]);
}

void test_known_ext_already_installed_returns_nil ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	python.installedSHA = @"deadbeef";
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	BundleSpec* hit = [reg bundleSpecForFileExtension:@"py"];
	OAK_ASSERT(hit == nil);
}

void test_unknown_ext_returns_nil ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	OAK_ASSERT([reg bundleSpecForFileExtension:@"xyz"] == nil);
}

void test_case_insensitive_lookup ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	BundleSpec* hitLower = [reg bundleSpecForFileExtension:@"py"];
	BundleSpec* hitUpper = [reg bundleSpecForFileExtension:@"PY"];
	BundleSpec* hitMixed = [reg bundleSpecForFileExtension:@"Py"];

	OAK_ASSERT(hitLower != nil);
	OAK_ASSERT(hitUpper != nil);
	OAK_ASSERT(hitMixed != nil);
	OAK_ASSERT([hitLower.uuid isEqual:hitUpper.uuid]);
	OAK_ASSERT([hitLower.uuid isEqual:hitMixed.uuid]);
}

void test_missing_index_file_returns_nil ()
{
	test::jail_t jail;
	NSString* indexPath = [NSString stringWithUTF8String:jail.path("nonexistent.plist").c_str()];

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	OAK_ASSERT([reg bundleSpecForFileExtension:@"py"] == nil);
	OAK_ASSERT([reg bundleSpecForFileExtension:@"rb"] == nil);
}

void test_nil_and_empty_ext_return_nil ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	OAK_ASSERT([reg bundleSpecForFileExtension:nil] == nil);
	OAK_ASSERT([reg bundleSpecForFileExtension:@""] == nil);
}

void test_index_references_unknown_uuid_returns_nil ()
{
	test::jail_t jail;
	NSString* indexPath = WriteIndex(jail, @{
		@"py": @{ @"bundleUUID": kGhostUUID, @"bundleName": @"Ghost" },
	});

	// Spec table has Python but the index points at a ghost UUID.
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = [[BundleRegistry alloc] initForTestingWithSpecs:@[ python ] fileTypeIndexPath:indexPath];

	OAK_ASSERT([reg bundleSpecForFileExtension:@"py"] == nil);
}
