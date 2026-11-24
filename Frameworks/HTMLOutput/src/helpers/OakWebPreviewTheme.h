#import <Foundation/Foundation.h>

@class NSMenu;

// The web preview themes that Bundle Support offers the HTML output page
// (Themes.tmbundle/Support/web-themes/<class>/style.css plus the user's
// ~/Library/Application Support/TextMate/Themes/Webpreview). The page links
// every theme's stylesheet and picks one by body class, so switching is a
// class change, no reload. The choice is stored where Bundle Support reads
// it: `SelectedTheme` in the com.macromates.textmate.webpreview domain.

extern NSString* const OakWebPreviewThemeDidChangeNotification; // object: the OakWebPreviewTheme
extern NSString* const kOakWebPreviewDefaultThemeClass;          // what Bundle Support falls back to

@interface OakWebPreviewTheme : NSObject
@property (nonatomic, readonly) NSString* name;      // "Bright"
@property (nonatomic, readonly) NSString* className; // "bright", the directory name and body class
@property (nonatomic, readonly) NSString* path;      // the theme directory
- (instancetype)initWithClassName:(NSString*)className path:(NSString*)path;
@end

// Themes found in `directories`, in Bundle Support's order: first directory
// wins a duplicate class, `default` is skipped, only directories with a
// style.css count. Sorted by name.
NSArray<OakWebPreviewTheme*>* OakWebPreviewThemesInDirectories (NSArray<NSString*>* directories);

// The directories Bundle Support scans, as far as the app can know them:
// $TM_THEME_PATH entries, the installed Themes bundle's web-themes, and the
// user's Webpreview folder.
NSArray<NSString*>* OakWebPreviewThemeDirectories ();

// The stored class, or kOakWebPreviewDefaultThemeClass when nothing is stored.
NSString* OakWebPreviewSelectedThemeClass ();

// Stores the class and posts OakWebPreviewThemeDidChangeNotification.
void OakWebPreviewSelectTheme (OakWebPreviewTheme* theme);

// JavaScript that switches an already loaded preview page to `theme`.
NSString* OakWebPreviewApplyThemeScript (OakWebPreviewTheme* theme);

// Fills `menu` with one item per theme (representedObject = the theme), the
// selected one checked, or a disabled placeholder when there are none.
void OakWebPreviewPopulateThemeMenu (NSMenu* menu, NSArray<OakWebPreviewTheme*>* themes, NSString* selectedClass, id target, SEL action);
