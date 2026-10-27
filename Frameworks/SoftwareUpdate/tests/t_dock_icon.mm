#import <SoftwareUpdate/SoftwareUpdate.h>

// AppKit rasterises NSApp.applicationIconImage at the image’s nominal size,
// and Icon Services hands back app icons at a nominal 32×32 points. Shipped
// as-is, the Dock and the ⌘Tab switcher get a 64×64 pixel bitmap and stretch
// it. The Dock icon helper must raise the size to the largest representation.

void test_dock_icon_image_is_full_size ()
{
	NSImage* icon = OakDockIconImageForBundleAtPath(@"/System/Applications/TextEdit.app");
	OAK_ASSERT(icon != nil);

	CGFloat largest = 0;
	for(NSImageRep* rep in icon.representations)
		largest = std::max(largest, std::max(rep.size.width, rep.size.height));

	OAK_ASSERT_GE(largest, 512);
	OAK_ASSERT_EQ(icon.size.width, largest);
	OAK_ASSERT_EQ(icon.size.height, largest);
}
