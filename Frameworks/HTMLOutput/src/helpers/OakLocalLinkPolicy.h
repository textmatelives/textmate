#import <Foundation/Foundation.h>

// What the HTML output view does with a navigation to a local file, i.e. a
// tm-file: or file: URL. Non-HTML files clicked in the preview are opened in
// TextMate; the web view only shows what it can render.
typedef NS_ENUM(NSInteger, OakLocalLinkAction) {
	OakLocalLinkActionLoad,   // let the web view load it
	OakLocalLinkActionOpen,   // open the file in TextMate
	OakLocalLinkActionScroll, // the document itself with a fragment: scroll in place
};

OakLocalLinkAction OakLocalLinkActionForURL (NSURL* url, BOOL linkActivated, NSString* documentPath);

// txmt://open?url=file://… for the given path, as handleTxMtURL: expects it.
NSURL* OakTxMtOpenURLForPath (NSString* path);

// JavaScript that moves the page to the fragment: location.hash = "…"
NSString* OakScrollToFragmentScript (NSString* fragment);
