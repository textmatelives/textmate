#import "BundleRegistryTesting.h"
#import "../src/BundleSpec.h"
#import "../src/MandatoryBundles.h"

// A registry that was created before a mandatory bundle moved to a new
// repository still carries the old url. Seeding restores the pinned url and
// sha, as the header promises, so a later pin bump can fetch from the new
// place on existing installs too.
void test_seeding_restores_pinned_url_and_sha_of_mandatory_bundles ()
{
	TMMandatoryBundle const& pinned = kTMMandatoryBundles[kTMMandatoryBundleCount - 1];
	NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:pinned.uuid]];

	BundleSpec* stale = [[BundleSpec alloc] initWithUUID:uuid name:[NSString stringWithUTF8String:pinned.name] url:@"https://github.com/example/old.tmbundle" ref:@"0000000000000000000000000000000000000000"];
	BundleRegistry* registry = [[BundleRegistry alloc] initForTestingWithSpecs:@[ stale ] fileTypeIndexPath:nil];
	[registry seedMandatory];

	BundleSpec* seeded = [registry specForUUID:uuid];
	OAK_ASSERT(seeded);
	OAK_ASSERT_EQ(std::string(seeded.url.UTF8String), std::string(pinned.url));
	OAK_ASSERT_EQ(std::string(seeded.ref.UTF8String), std::string(pinned.sha));
	OAK_ASSERT(seeded.origin == TMBundleOriginMandatory);
}
