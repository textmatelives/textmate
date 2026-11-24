#import <Foundation/Foundation.h>

// Zoom of the HTML output views, on top of the interface scale factor.
// Shared by every output view and remembered across launches.

extern NSString* const kUserDefaultsWebPreviewZoomKey;
extern NSString* const OakWebPreviewZoomDidChangeNotification;

extern double const kOakWebPreviewZoomMinimum;
extern double const kOakWebPreviewZoomMaximum;

// One step up (+1) or down (-1) from `zoom`, clamped to the range.
double OakWebPreviewZoomStep (double zoom, int direction);

// The remembered zoom, 1.0 when nothing is stored or the value is out of range.
double OakWebPreviewZoom ();

// Stores `zoom` (clamped) and posts OakWebPreviewZoomDidChangeNotification.
void OakWebPreviewSetZoom (double zoom);
