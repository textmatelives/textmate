#import <Foundation/Foundation.h>

// Compile-time pinned list of bundles required by TextMate to function.
// Users cannot remove, disable, or repoint these via the bundle registry.
//
// The `sha` field IS the pinned ref — bundles are always fetched (and
// embedded) at this exact commit. Branch names are documented in the
// trailing comment for human reference only; bumping the pin is done by
// editing this file and re-running bin/fetch_embedded_bundles.sh.
//
// Matching tmbundle directories are embedded inside the .app under
// Contents/SharedSupport/Bundles/<name>.tmbundle/ so a fresh launch with
// no network still yields a functional editor.

struct TMMandatoryBundle
{
	char const* uuid;
	char const* name;
	char const* url;
	char const* sha;
	char const* category;
};

static struct TMMandatoryBundle const kTMMandatoryBundles[] = {
	// branch: remove-legacy-ruby
	{
		"0BB1F01A-4F0A-475A-ACDD-0F5578F2EFC3",
		"Bundle Support",
		"https://github.com/dayglojesus/bundle-support.tmbundle",
		"7c779d06bab86a9e0d5d9d7121d43ce9869e9856",
		"Other",
	},
	// branch: remove-legacy-ruby
	{
		"B7BC3FFD-6E4B-11D9-91AF-000D93589AF6",
		"Text",
		"https://github.com/dayglojesus/text.tmbundle",
		"34ab58910c42f53798f19dd2cba3d7732a3e8d03",
		"Other",
	},
	// branch: remove-legacy-ruby
	{
		"4F45FDC0-62CA-4786-9134-8BC7C1F5606F",
		"Source",
		"https://github.com/dayglojesus/source.tmbundle",
		"2c873f8382fd11cda4a86b4159bc2977577568d3",
		"Other",
	},
	// branch: master (upstream textmate/themes.tmbundle — pure data, no Ruby)
	{
		"A4380B27-F366-4C70-A542-B00D26ED997E",
		"Themes",
		"https://github.com/textmate/themes.tmbundle",
		"e6e918506291b2dec178ad1b7e6f04653d25818c",
		"Themes",
	},
};

static size_t const kTMMandatoryBundleCount = sizeof(kTMMandatoryBundles) / sizeof(kTMMandatoryBundles[0]);
