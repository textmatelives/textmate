#import <Cocoa/Cocoa.h>

// Appearance of the HTML output views: light, dark, or the app's own.
// Shared by every output view and remembered across launches, so a dark
// interface can show previews in light colours, as Mail and Word allow.

extern NSString* const kUserDefaultsWebPreviewAppearanceKey; // @"light", @"dark", or absent
extern NSString* const OakWebPreviewAppearanceDidChangeNotification;

// The stored mode, @"light" or @"dark", or nil when the preview follows the app.
NSString* OakWebPreviewAppearanceMode ();

// The appearance to set on an output view for the stored mode, nil to inherit.
NSAppearance* OakWebPreviewAppearance ();

// Stores `mode` (nil or an unknown value clears it) and posts OakWebPreviewAppearanceDidChangeNotification.
void OakWebPreviewSetAppearanceMode (NSString* mode);
