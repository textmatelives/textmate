#import <SoftwareUpdate/SoftwareUpdate.h>

// Builds a git smart-HTTP ref advertisement (the response to
// GET /info/refs?service=git-upload-pack). Format verified against a live
// capture from github.com on 2026-06-11: each pkt-line is a 4-hex-digit
// length (including the 4 length bytes) followed by the payload; "0000" is
// a flush packet; the first ref pkt carries "\0capabilities" after the name.
static NSData* str (NSString* s)
{
	return [s dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData* with_capabilities (NSString* shaAndName, NSString* capabilities)
{
	NSMutableData* payload = [str(shaAndName) mutableCopy];
	[payload appendBytes:"\0" length:1];
	[payload appendData:str([capabilities stringByAppendingString:@"\n"])];
	return payload;
}

static NSData* advertisement (NSArray<NSData*>* payloads)
{
	NSMutableData* data = [NSMutableData data];
	void(^pkt)(NSData*) = ^(NSData* payload){
		[data appendData:str([NSString stringWithFormat:@"%04lx", payload.length + 4])];
		[data appendData:payload];
	};

	pkt(str(@"# service=git-upload-pack\n"));
	[data appendData:str(@"0000")];
	for(NSData* payload in payloads)
		pkt(payload);
	[data appendData:str(@"0000")];
	return data;
}

static NSString* const kHeadSHA      = @"697d3690df4b2825e23c1a5d3bcd0e6b072e2c3d";
static NSString* const kBranchSHA    = @"61f251d131a72463ece57a19c2c43bea98535398";
static NSString* const kTagObjectSHA = @"08b34233a7029b729979fd7fd41dea326c90432f";
static NSString* const kPeeledSHA    = @"a5d3bcd0e6b072e2c3d697d3690df4b2825e23c1";

static NSData* sample ()
{
	return advertisement(@[
		with_capabilities([NSString stringWithFormat:@"%@ HEAD", kHeadSHA], @"multi_ack thin-pack symref=HEAD:refs/heads/main agent=git/github"),
		str([NSString stringWithFormat:@"%@ refs/heads/main\n", kHeadSHA]),
		str([NSString stringWithFormat:@"%@ refs/heads/feature/x\n", kBranchSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/1.0.0\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2^{}\n", kPeeledSHA]),
	]);
}

// ==============================================
// = OakSHAForRefInUploadPackAdvertisement      =
// ==============================================

void test_branch_resolution ()
{
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"main") isEqualToString:kHeadSHA]);
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"feature/x") isEqualToString:kBranchSHA]);
}

void test_tag_resolution ()
{
	// Lightweight tag: the ref's own SHA is the commit.
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"1.0.0") isEqualToString:kTagObjectSHA]);
	// Annotated tag: prefer the peeled (^{}) commit SHA over the tag object.
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"v2") isEqualToString:kPeeledSHA]);
}

void test_head_and_qualified_refs ()
{
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"HEAD") isEqualToString:kHeadSHA]);
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"refs/heads/main") isEqualToString:kHeadSHA]);
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(sample(), @"refs/tags/v2") isEqualToString:kPeeledSHA]);
}

void test_branch_shadows_tag ()
{
	// A name existing as both branch and tag resolves to the branch,
	// matching git's refs/heads-before-refs/tags disambiguation.
	NSData* data = advertisement(@[
		str([NSString stringWithFormat:@"%@ refs/heads/v2\n", kBranchSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2\n", kTagObjectSHA]),
	]);
	OAK_ASSERT([OakSHAForRefInUploadPackAdvertisement(data, @"v2") isEqualToString:kBranchSHA]);
}

void test_unresolvable_inputs ()
{
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(sample(), @"no-such-ref") == nil);
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(sample(), @"") == nil);
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(sample(), nil) == nil);
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(nil, @"main") == nil);
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(str(@"HTTP/1.1 403 Forbidden"), @"main") == nil);
	OAK_ASSERT(OakSHAForRefInUploadPackAdvertisement(str(@"00zz"), @"main") == nil);
}

// ====================================================
// = OakLatestVersionInUploadPackAdvertisement        =
// ====================================================

// Tag layout mirroring the real textmatelives/textmate repo plus synthetic
// betas and experimental builds; deliberately listed out of version order,
// since the advertisement is sorted by ref name, not version. The
// experimental tags sit at 2.3.0 — above every stable and beta tag here —
// because that is the case that leaks: nothing about being newer may make
// an experiment visible to a channel that did not ask for it.
static NSData* version_tags ()
{
	return advertisement(@[
		with_capabilities([NSString stringWithFormat:@"%@ HEAD", kHeadSHA], @"symref=HEAD:refs/heads/main agent=git/github"),
		str([NSString stringWithFormat:@"%@ refs/heads/main\n", kHeadSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.0.23-undead.0\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.0-undead\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.10-undead-beta.2\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.10-undead-beta.10\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.2-undead\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.2-undead^{}\n", kPeeledSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.1-undead\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.3.0-undead-exp.2\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.3.0-undead-exp.10\n", kTagObjectSHA]),
	]);
}

void test_latest_version_release_channel_excludes_prereleases ()
{
	// Both 2.1.10-undead-beta.* and 2.3.0-undead-exp.* outrank 2.1.2-undead
	// per OakCompareVersionStrings; the release channel must see neither.
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(version_tags(), kSoftwareUpdateChannelRelease) isEqualToString:@"2.1.2-undead"]);
}

void test_latest_version_beta_channel_includes_betas_not_experiments ()
{
	// Max among stable+beta — and numerically: beta.10 > beta.2. The newer
	// experimental tags stay invisible, or opting into betas would drag the
	// user onto an experiment they never asked for.
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(version_tags(), kSoftwareUpdateChannelPrerelease) isEqualToString:@"2.1.10-undead-beta.10"]);
}

void test_latest_version_experimental_channel_sees_only_experiments ()
{
	// Deliberately no convergence onto stable: an experimental stream may
	// never merge, so offering the newest stable would silently take away
	// the feature the user opted in to test. Also numeric: exp.10 > exp.2.
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(version_tags(), kSoftwareUpdateChannelExperimental) isEqualToString:@"2.3.0-undead-exp.10"]);
}

void test_latest_version_unknown_channel_is_treated_as_stable ()
{
	// A channel string from a future build (or a hand-edited default) must
	// not fall through to something more permissive than release.
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(version_tags(), @"no-such-channel") isEqualToString:@"2.1.2-undead"]);
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(version_tags(), nil) isEqualToString:@"2.1.2-undead"]);
}

void test_latest_version_ignores_non_version_refs ()
{
	// Branches, vNonDigit tags, and tags without the v prefix don't qualify.
	NSData* data = advertisement(@[
		str([NSString stringWithFormat:@"%@ refs/heads/v9.9.9\n", kBranchSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/vendor-drop\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/3.0.0\n", kTagObjectSHA]),
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.1-undead\n", kTagObjectSHA]),
	]);
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(data, kSoftwareUpdateChannelPrerelease) isEqualToString:@"2.1.1-undead"]);

	// Only beta tags exist → the release channel finds nothing.
	NSData* betasOnly = advertisement(@[
		str([NSString stringWithFormat:@"%@ refs/tags/v2.1.2-undead-beta.1\n", kTagObjectSHA]),
	]);
	OAK_ASSERT(OakLatestVersionInUploadPackAdvertisement(betasOnly, kSoftwareUpdateChannelRelease) == nil);
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(betasOnly, kSoftwareUpdateChannelPrerelease) isEqualToString:@"2.1.2-undead-beta.1"]);

	// No experimental tags → the experimental channel finds nothing rather
	// than falling back to stable.
	OAK_ASSERT(OakLatestVersionInUploadPackAdvertisement(betasOnly, kSoftwareUpdateChannelExperimental) == nil);
}

void test_latest_version_malformed_or_empty ()
{
	OAK_ASSERT(OakLatestVersionInUploadPackAdvertisement(nil, kSoftwareUpdateChannelPrerelease) == nil);
	OAK_ASSERT(OakLatestVersionInUploadPackAdvertisement(str(@"HTTP/1.1 403 Forbidden"), kSoftwareUpdateChannelPrerelease) == nil);
	OAK_ASSERT(OakLatestVersionInUploadPackAdvertisement(advertisement(@[ ]), kSoftwareUpdateChannelPrerelease) == nil);
	// sample() carries tags “1.0.0” (no v prefix — skipped) and “v2” (qualifies).
	OAK_ASSERT([OakLatestVersionInUploadPackAdvertisement(sample(), kSoftwareUpdateChannelRelease) isEqualToString:@"2"]);
}

// ====================================
// = OakUpdateAssetURLForVersion      =
// ====================================

void test_asset_url_from_advertisement_url ()
{
	// release.yml uploads TextMate-{version}.tbz onto release v{version}; the
	// asset URL is derived from the advertisement URL by convention.
	NSURL* feed = [NSURL URLWithString:@"https://github.com/textmatelives/textmate.git/info/refs?service=git-upload-pack"];
	NSURL* expected = [NSURL URLWithString:@"https://github.com/textmatelives/textmate/releases/download/v2.1.2-undead/TextMate-2.1.2-undead.tbz"];
	OAK_ASSERT([OakUpdateAssetURLForVersion(@"2.1.2-undead", feed) isEqual:expected]);
}

void test_asset_url_rejects_malformed_inputs ()
{
	NSURL* feed = [NSURL URLWithString:@"https://github.com/textmatelives/textmate.git/info/refs?service=git-upload-pack"];
	OAK_ASSERT(OakUpdateAssetURLForVersion(nil, feed) == nil);
	OAK_ASSERT(OakUpdateAssetURLForVersion(@"", feed) == nil);
	OAK_ASSERT(OakUpdateAssetURLForVersion(@"2.1.2-undead", nil) == nil);
	OAK_ASSERT(OakUpdateAssetURLForVersion(@"2.1.2-undead", [NSURL URLWithString:@"https://github.com/textmatelives/textmate"]) == nil);
	OAK_ASSERT(OakUpdateAssetURLForVersion(@"2.1.2-undead", [NSURL URLWithString:@"https://api.github.com/repos/textmatelives/textmate/releases/latest"]) == nil);
}
