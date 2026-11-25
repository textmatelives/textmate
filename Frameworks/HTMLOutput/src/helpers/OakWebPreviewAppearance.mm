#import "OakWebPreviewAppearance.h"

NSString* const kUserDefaultsWebPreviewAppearanceKey         = @"webPreviewAppearance";
NSString* const OakWebPreviewAppearanceDidChangeNotification = @"OakWebPreviewAppearanceDidChangeNotification";

static NSString* const kLight = @"light";
static NSString* const kDark  = @"dark";

NSString* OakWebPreviewAppearanceMode ()
{
	NSString* mode = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsWebPreviewAppearanceKey];
	return [mode isEqualToString:kLight] || [mode isEqualToString:kDark] ? mode : nil;
}

NSAppearance* OakWebPreviewAppearance ()
{
	NSString* mode = OakWebPreviewAppearanceMode();
	if(!mode)
		return nil;
	return [NSAppearance appearanceNamed:[mode isEqualToString:kDark] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
}

void OakWebPreviewSetAppearanceMode (NSString* mode)
{
	if([mode isEqualToString:kLight] || [mode isEqualToString:kDark])
			[NSUserDefaults.standardUserDefaults setObject:mode forKey:kUserDefaultsWebPreviewAppearanceKey];
	else	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsWebPreviewAppearanceKey];
	[NSNotificationCenter.defaultCenter postNotificationName:OakWebPreviewAppearanceDidChangeNotification object:nil];
}
