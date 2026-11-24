#import "OakWebPreviewZoom.h"

NSString* const kUserDefaultsWebPreviewZoomKey        = @"webPreviewZoom";
NSString* const OakWebPreviewZoomDidChangeNotification = @"OakWebPreviewZoomDidChangeNotification";

double const kOakWebPreviewZoomMinimum = 0.5;
double const kOakWebPreviewZoomMaximum = 3.0;

static double const kZoomStepFactor = 1.1;

static double clamp (double zoom)
{
	if(!(zoom > 0)) // also catches NaN
		return 1.0;
	return MIN(MAX(zoom, kOakWebPreviewZoomMinimum), kOakWebPreviewZoomMaximum);
}

double OakWebPreviewZoomStep (double zoom, int direction)
{
	zoom = clamp(zoom);
	if(direction > 0)
		zoom *= kZoomStepFactor;
	else if(direction < 0)
		zoom /= kZoomStepFactor;
	// Snap to two decimals so stepping up then down lands back on 1.0
	return clamp(round(zoom * 100) / 100);
}

double OakWebPreviewZoom ()
{
	NSNumber* stored = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsWebPreviewZoomKey];
	if(![stored isKindOfClass:[NSNumber class]])
		return 1.0;
	double zoom = stored.doubleValue;
	return zoom >= kOakWebPreviewZoomMinimum && zoom <= kOakWebPreviewZoomMaximum ? zoom : 1.0;
}

void OakWebPreviewSetZoom (double zoom)
{
	zoom = clamp(zoom);
	if(zoom == 1.0)
			[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsWebPreviewZoomKey];
	else	[NSUserDefaults.standardUserDefaults setDouble:zoom forKey:kUserDefaultsWebPreviewZoomKey];
	[NSNotificationCenter.defaultCenter postNotificationName:OakWebPreviewZoomDidChangeNotification object:nil];
}
