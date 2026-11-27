#import <OakTextView/OakTextView.h>

// The SCM gutter resolves mark types to template PDFs by name
// (OakDocumentView gutterImage: appends " Template"). A malformed PDF
// fails silently to nil, so lock the canvas contract for each asset.

static NSImage* LoadResourcePDF (NSString* name)
{
	NSString* testsDir = [@(__FILE__) stringByDeletingLastPathComponent];
	NSString* path = [[testsDir stringByAppendingPathComponent:@"../resources"] stringByAppendingPathComponent:name];
	return [[NSImage alloc] initWithContentsOfFile:path];
}

void test_diff_gutter_assets_load ()
{
	for(NSString* name in @[ @"diff.added Template.pdf", @"diff.modified Template.pdf", @"diff.deleted Template.pdf" ])
	{
		NSImage* image = LoadResourcePDF(name);
		OAK_ASSERT(image != nil);
		OAK_ASSERT_EQ(image.size.width, 13);
		OAK_ASSERT_EQ(image.size.height, 6);
	}
}
