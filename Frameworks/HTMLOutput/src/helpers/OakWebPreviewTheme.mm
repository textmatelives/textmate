#import "OakWebPreviewTheme.h"
#import <bundles/bundles.h>
#import <io/path.h>
#import <ns/ns.h>
#import <text/parse.h>

NSString* const OakWebPreviewThemeDidChangeNotification = @"OakWebPreviewThemeDidChangeNotification";
NSString* const kOakWebPreviewDefaultThemeClass          = @"bright";

static CFStringRef const kWebPreviewDomain      = CFSTR("com.macromates.textmate.webpreview");
static CFStringRef const kSelectedThemeKey      = CFSTR("SelectedTheme");
static NSString* const kThemesBundleUUID        = @"A4380B27-F366-4C70-A542-B00D26ED997E";

@implementation OakWebPreviewTheme
- (instancetype)initWithClassName:(NSString*)className path:(NSString*)path
{
	if(self = [super init])
	{
		_className = [className copy];
		_path      = [path copy];
		_name      = [[className substringToIndex:1].uppercaseString stringByAppendingString:[className substringFromIndex:1]];
	}
	return self;
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@ (%@)>", self.class, _className, _path];
}
@end

NSArray<OakWebPreviewTheme*>* OakWebPreviewThemesInDirectories (NSArray<NSString*>* directories)
{
	NSMutableArray<OakWebPreviewTheme*>* res = [NSMutableArray array];
	NSMutableSet<NSString*>* seen = [NSMutableSet set];
	NSFileManager* fm = NSFileManager.defaultManager;

	for(NSString* directory in directories)
	{
		for(NSString* entry in [fm contentsOfDirectoryAtPath:directory error:nil])
		{
			if([seen containsObject:entry])
				continue;
			[seen addObject:entry];

			if([entry isEqualToString:@"default"] || [entry hasPrefix:@"."])
				continue;

			NSString* themePath = [directory stringByAppendingPathComponent:entry];
			if([fm fileExistsAtPath:[themePath stringByAppendingPathComponent:@"style.css"]])
				[res addObject:[[OakWebPreviewTheme alloc] initWithClassName:entry path:themePath]];
		}
	}

	return [res sortedArrayUsingComparator:^NSComparisonResult(OakWebPreviewTheme* lhs, OakWebPreviewTheme* rhs){
		return [lhs.name localizedCaseInsensitiveCompare:rhs.name];
	}];
}

NSArray<NSString*>* OakWebPreviewThemeDirectories ()
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];

	if(char const* themePath = getenv("TM_THEME_PATH"))
	{
		for(auto const& dir : text::split(themePath, ":"))
		{
			if(!dir.empty())
				[res addObject:to_ns(dir)];
		}
	}

	if(bundles::item_ptr themesBundle = bundles::lookup(oak::uuid_t(kThemesBundleUUID.UTF8String)))
	{
		for(auto const& path : themesBundle->paths())
		{
			std::string bundlePath = path::extension(path) == ".tmbundle" ? path : path::parent(path); // bundle items carry their info.plist path
			[res addObject:to_ns(path::join(bundlePath, "Support/web-themes"))];
		}
	}

	[res addObject:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TextMate/Themes/Webpreview"]];
	return res;
}

NSString* OakWebPreviewSelectedThemeClass ()
{
	NSString* stored = (__bridge_transfer NSString*)CFPreferencesCopyAppValue(kSelectedThemeKey, kWebPreviewDomain);
	return [stored isKindOfClass:[NSString class]] && stored.length ? stored : kOakWebPreviewDefaultThemeClass;
}

void OakWebPreviewSelectTheme (OakWebPreviewTheme* theme)
{
	CFPreferencesSetAppValue(kSelectedThemeKey, (__bridge CFStringRef)theme.className, kWebPreviewDomain);
	CFPreferencesAppSynchronize(kWebPreviewDomain);
	[NSNotificationCenter.defaultCenter postNotificationName:OakWebPreviewThemeDidChangeNotification object:theme];
}

NSString* OakWebPreviewApplyThemeScript (OakWebPreviewTheme* theme)
{
	NSData* json = [NSJSONSerialization dataWithJSONObject:theme.className options:NSJSONWritingFragmentsAllowed error:nil];
	NSString* quoted = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	// Mirrors selectTheme() in Bundle Support's webpreview.js, minus the header images, which the app hides.
	return [NSString stringWithFormat:@"(function(){ var theme = %@; for(var id of ['tm_webpreview_body', 'tm_webpreview_content']) { var e = document.getElementById(id); if(e) e.className = theme; } })();", quoted];
}

void OakWebPreviewPopulateThemeMenu (NSMenu* menu, NSArray<OakWebPreviewTheme*>* themes, NSString* selectedClass, id target, SEL action)
{
	[menu removeAllItems];
	if(themes.count == 0)
	{
		NSMenuItem* item = [menu addItemWithTitle:@"No Preview Themes Found" action:NULL keyEquivalent:@""];
		item.enabled = NO;
		return;
	}

	for(OakWebPreviewTheme* theme in themes)
	{
		NSMenuItem* item = [menu addItemWithTitle:theme.name action:action keyEquivalent:@""];
		item.target = target;
		item.representedObject = theme;
		item.state = [theme.className isEqualToString:selectedClass] ? NSControlStateValueOn : NSControlStateValueOff;
	}
}
