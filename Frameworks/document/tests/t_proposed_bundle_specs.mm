#import "../src/OakDocument.h"
#import "../src/OakDocument Private.h"
#import <BundlesManager/BundleSpec.h>
#import <BundlesManager/BundleRegistry.h>
#import <test/jail.h>

// Phase 2: OakDocument.proposedBundleSpecs returns uninstalled catalogue
// bundles claiming the document's path extension. The accessor delegates to
// -[BundleRegistry bundleSpecForFileExtension:]; this exercises the
// document-side gating (no path → empty, no extension → empty) and verifies
// the registry pass-through.

static NSString* const kPythonUUID = @"E12C1C8B-25B0-4A28-9E9D-1D2C9E5C49A5";
static NSString* const kRubyUUID   = @"467B298F-6227-11D9-BFB1-000D93589AF6";

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

static BundleRegistry* MakeRegistry (test::jail_t const& jail, NSArray<BundleSpec*>* specs, NSDictionary* index)
{
	NSString* path = WriteIndex(jail, index);
	return [[BundleRegistry alloc] initForTestingWithSpecs:specs fileTypeIndexPath:path];
}

void test_untitled_document_returns_empty ()
{
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:nil];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT(specs != nil);
	OAK_ASSERT_EQ(specs.count, 0u);
}

void test_document_no_extension_returns_empty ()
{
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/Makefile"];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT(specs != nil);
	OAK_ASSERT_EQ(specs.count, 0u);
}

void test_known_extension_uninstalled_returns_spec ()
{
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/hello.py"];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT_EQ(specs.count, 1u);
	OAK_ASSERT([specs.firstObject.uuid isEqual:python.uuid]);
}

void test_known_extension_installed_returns_empty ()
{
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	python.installedSHA = @"deadbeef";  // Mark as installed
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/hello.py"];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT_EQ(specs.count, 0u);
}

void test_unknown_extension_returns_empty ()
{
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/unknown.xyz"];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT_EQ(specs.count, 0u);
}

void test_uppercase_extension_resolves ()
{
	// BundleRegistry.bundleSpecForFileExtension: lowercases. Verify the
	// document-side path-extension extraction passes through correctly.
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/HELLO.PY"];
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT_EQ(specs.count, 1u);
}

void test_virtual_path_takes_precedence ()
{
	// virtualPath is used for file-type detection (rmate). Mirror the same
	// precedence rule that proposedGrammars applies (line 1243 of
	// OakDocument.mm: to_s(_virtualPath ?: _path)).
	test::jail_t jail;
	BundleSpec* python = MakeSpec(kPythonUUID, @"Python");
	BundleRegistry* reg = MakeRegistry(jail, @[ python ], @{
		@"py": @{ @"bundleUUID": kPythonUUID, @"bundleName": @"Python" },
	});

	OakDocument* doc = [[OakDocument alloc] initWithPath:@"/tmp/no_ext_here"];
	doc.virtualPath = @"/tmp/actually.py";
	NSArray<BundleSpec*>* specs = [doc proposedBundleSpecsUsingRegistry:reg];
	OAK_ASSERT_EQ(specs.count, 1u);
}
