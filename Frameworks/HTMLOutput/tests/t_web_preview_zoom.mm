#import "../src/helpers/OakWebPreviewZoom.h"

// Zoom steps are multiplicative, snap to two decimals so a round trip returns
// to 1.0, and stay inside the range.
void test_zoom_steps_round_trip ()
{
	double up = OakWebPreviewZoomStep(1.0, +1);
	OAK_ASSERT_GT(up, 1.0);
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(up, -1), 1.0);
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(1.0, 0), 1.0);
}

void test_zoom_steps_are_clamped ()
{
	double zoom = kOakWebPreviewZoomMaximum;
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(zoom, +1), kOakWebPreviewZoomMaximum);
	zoom = kOakWebPreviewZoomMinimum;
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(zoom, -1), kOakWebPreviewZoomMinimum);
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(0, +1), OakWebPreviewZoomStep(1.0, +1));
	OAK_ASSERT_EQ(OakWebPreviewZoomStep(NAN, -1), OakWebPreviewZoomStep(1.0, -1));
}

void test_stored_zoom_is_validated ()
{
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	id saved = [defaults objectForKey:kUserDefaultsWebPreviewZoomKey];

	[defaults removeObjectForKey:kUserDefaultsWebPreviewZoomKey];
	OAK_ASSERT_EQ(OakWebPreviewZoom(), 1.0);

	[defaults setObject:@"big" forKey:kUserDefaultsWebPreviewZoomKey];
	OAK_ASSERT_EQ(OakWebPreviewZoom(), 1.0);

	[defaults setDouble:42 forKey:kUserDefaultsWebPreviewZoomKey];
	OAK_ASSERT_EQ(OakWebPreviewZoom(), 1.0);

	__block NSUInteger notifications = 0;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:OakWebPreviewZoomDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification*){ ++notifications; }];
	OakWebPreviewSetZoom(1.5);
	OAK_ASSERT_EQ(OakWebPreviewZoom(), 1.5);
	OakWebPreviewSetZoom(1.0);
	OAK_ASSERT_EQ(OakWebPreviewZoom(), 1.0);
	OAK_ASSERT_EQ(notifications, 2);
	OAK_ASSERT([defaults objectForKey:kUserDefaultsWebPreviewZoomKey] == nil); // 1.0 is not stored
	[NSNotificationCenter.defaultCenter removeObserver:observer];

	if(saved)
			[defaults setObject:saved forKey:kUserDefaultsWebPreviewZoomKey];
	else	[defaults removeObjectForKey:kUserDefaultsWebPreviewZoomKey];
}
