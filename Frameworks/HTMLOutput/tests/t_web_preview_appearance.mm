#import "../src/helpers/OakWebPreviewAppearance.h"
#import <ns/ns.h>

// The preview appearance is light, dark, or absent (follow the app). Anything
// else stored in the defaults counts as absent; setting a mode stores it and notifies.
void test_appearance_mode_is_validated_stored_and_notified ()
{
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	id saved = [defaults objectForKey:kUserDefaultsWebPreviewAppearanceKey];

	[defaults removeObjectForKey:kUserDefaultsWebPreviewAppearanceKey];
	OAK_ASSERT(OakWebPreviewAppearanceMode() == nil);
	OAK_ASSERT(OakWebPreviewAppearance() == nil);

	[defaults setObject:@"sepia" forKey:kUserDefaultsWebPreviewAppearanceKey];
	OAK_ASSERT(OakWebPreviewAppearanceMode() == nil);

	[defaults setObject:@42 forKey:kUserDefaultsWebPreviewAppearanceKey];
	OAK_ASSERT(OakWebPreviewAppearanceMode() == nil);

	[defaults setObject:@"dark" forKey:kUserDefaultsWebPreviewAppearanceKey];
	OAK_ASSERT_EQ(to_s(OakWebPreviewAppearanceMode()), "dark");
	OAK_ASSERT_EQ(to_s(OakWebPreviewAppearance().name), to_s(NSAppearanceNameDarkAqua));

	[defaults setObject:@"light" forKey:kUserDefaultsWebPreviewAppearanceKey];
	OAK_ASSERT_EQ(to_s(OakWebPreviewAppearance().name), to_s(NSAppearanceNameAqua));

	// Same test function on purpose: the runner executes tests in parallel and both halves touch one defaults key

	__block NSUInteger notifications = 0;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:OakWebPreviewAppearanceDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification*){ ++notifications; }];

	OakWebPreviewSetAppearanceMode(@"dark");
	OAK_ASSERT_EQ(to_s([defaults stringForKey:kUserDefaultsWebPreviewAppearanceKey]), "dark");
	OAK_ASSERT_EQ(notifications, 1);

	OakWebPreviewSetAppearanceMode(nil); // back to following the app: nothing stored
	OAK_ASSERT([defaults objectForKey:kUserDefaultsWebPreviewAppearanceKey] == nil);
	OAK_ASSERT_EQ(notifications, 2);

	OakWebPreviewSetAppearanceMode(@"sepia"); // unknown modes are treated as ‘follow the app’
	OAK_ASSERT([defaults objectForKey:kUserDefaultsWebPreviewAppearanceKey] == nil);
	OAK_ASSERT_EQ(notifications, 3);

	[NSNotificationCenter.defaultCenter removeObserver:observer];
	if(saved)
			[defaults setObject:saved forKey:kUserDefaultsWebPreviewAppearanceKey];
	else	[defaults removeObjectForKey:kUserDefaultsWebPreviewAppearanceKey];
}
