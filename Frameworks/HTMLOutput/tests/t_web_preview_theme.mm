#import "../src/helpers/OakWebPreviewTheme.h"
#import <test/jail.h>

static NSString* ns (std::string const& str) { return [NSString stringWithUTF8String:str.c_str()]; }

// Discovery follows Bundle Support's collect_themes: a theme is a directory
// with a style.css, `default` is not offered, the first directory to use a
// class name wins, and the list is sorted by display name.
void test_discovers_themes_like_bundle_support ()
{
	test::jail_t jail;
	jail.touch("bundle/bright/style.css");
	jail.touch("bundle/plain/style.css");
	jail.touch("bundle/default/style.css");
	jail.touch("bundle/default/print.css");
	jail.touch("bundle/images/header.png"); // a directory without style.css
	jail.touch("user/night/style.css");
	jail.touch("user/plain/style.css");      // duplicate class, loses to the bundle's

	NSArray<OakWebPreviewTheme*>* themes = OakWebPreviewThemesInDirectories(@[ ns(jail.path("bundle")), ns(jail.path("user")) ]);

	NSMutableArray* classes = [NSMutableArray array];
	for(OakWebPreviewTheme* theme in themes)
		[classes addObject:theme.className];
	OAK_ASSERT([classes isEqualToArray:(@[ @"bright", @"night", @"plain" ])]);
	OAK_ASSERT([themes[0].name isEqualToString:@"Bright"]);
	OAK_ASSERT([themes[2].path isEqualToString:ns(jail.path("bundle/plain"))]);
}

void test_missing_directories_are_ignored ()
{
	test::jail_t jail;
	OAK_ASSERT_EQ(OakWebPreviewThemesInDirectories(@[ ns(jail.path("nowhere")) ]).count, 0);
}

void test_apply_script_switches_the_body_and_content_classes ()
{
	OakWebPreviewTheme* theme = [[OakWebPreviewTheme alloc] initWithClassName:@"night" path:@"/tmp/night"];
	NSString* script = OakWebPreviewApplyThemeScript(theme);
	OAK_ASSERT([script containsString:@"var theme = \"night\";"]);
	OAK_ASSERT([script containsString:@"'tm_webpreview_body'"]);
	OAK_ASSERT([script containsString:@"'tm_webpreview_content'"]);
	OAK_ASSERT([script containsString:@"className = theme"]);
}

void test_menu_lists_themes_and_checks_the_selected_one ()
{
	NSArray* themes = @[
		[[OakWebPreviewTheme alloc] initWithClassName:@"bright" path:@"/tmp/bright"],
		[[OakWebPreviewTheme alloc] initWithClassName:@"night"  path:@"/tmp/night"],
	];
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Preview Theme"];
	OakWebPreviewPopulateThemeMenu(menu, themes, @"night", nil, @selector(copy:));

	OAK_ASSERT_EQ(menu.numberOfItems, 2);
	OAK_ASSERT([[menu itemAtIndex:0].title isEqualToString:@"Bright"]);
	OAK_ASSERT_EQ([menu itemAtIndex:0].state, NSControlStateValueOff);
	OAK_ASSERT_EQ([menu itemAtIndex:1].state, NSControlStateValueOn);
	OAK_ASSERT([menu itemAtIndex:1].representedObject == themes[1]);
	OAK_ASSERT([menu itemAtIndex:1].action == @selector(copy:));

	OakWebPreviewPopulateThemeMenu(menu, @[ ], @"bright", nil, @selector(copy:));
	OAK_ASSERT_EQ(menu.numberOfItems, 1);
	OAK_ASSERT(![menu itemAtIndex:0].enabled);
}
