#import <TMFileReference/TMFileReference.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// A file deleted under version control keeps the icon of its type, drawn
// dimmed, so the deletion badge carries the meaning and the icon still says
// what kind of file it was. The test runner has no DocumentTypes resources,
// so TextMate’s own icons and the badge are absent here and the base icon
// comes from the system by extension.

static NSData* Pixels (NSImage* image)
{
	NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:16 pixelsHigh:16 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
	[NSGraphicsContext saveGraphicsState];
	NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[image drawInRect:NSMakeRect(0, 0, 16, 16) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
	[NSGraphicsContext restoreGraphicsState];
	return [NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * 16];
}

static NSImage* Dimmed (NSImage* base)
{
	return [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect){
		[base drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:0.4];
		return YES;
	}];
}

static TMFileReference* DeletedReference (NSString* name)
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	TMFileReference* ref = [TMFileReference fileReferenceWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]];
	ref.SCMStatus = scm::status::deleted;
	return ref;
}

void test_deleted_file_shows_its_type_icon_dimmed ()
{
	NSImage* expected = Dimmed([NSWorkspace.sharedWorkspace iconForContentType:[UTType typeWithFilenameExtension:@"png"]]);
	OAK_ASSERT([Pixels(DeletedReference(@"photo.png").image) isEqualToData:Pixels(expected)]);
}

void test_deleted_files_of_different_types_differ ()
{
	OAK_ASSERT(![Pixels(DeletedReference(@"photo.png").image) isEqualToData:Pixels(DeletedReference(@"notes.txt").image)]);
}

void test_deleted_file_without_extension_uses_generic_icon ()
{
	NSImage* expected = Dimmed([NSWorkspace.sharedWorkspace iconForContentType:UTTypeData]);
	OAK_ASSERT([Pixels(DeletedReference(@"README").image) isEqualToData:Pixels(expected)]);
}

void test_deleted_folder_shows_a_folder_icon_dimmed ()
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	TMFileReference* ref = [TMFileReference fileReferenceWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"gone"] isDirectory:YES]];
	ref.SCMStatus = scm::status::deleted;
	NSImage* expected = Dimmed([NSWorkspace.sharedWorkspace iconForContentType:UTTypeFolder]);
	OAK_ASSERT([Pixels(ref.image) isEqualToData:Pixels(expected)]);
}

void test_deleted_file_is_dimmer_than_a_live_one ()
{
	// The live icon for a path that does not exist is unavailable, so compare
	// against the undimmed system icon for the type.
	NSImage* live = [NSWorkspace.sharedWorkspace iconForContentType:[UTType typeWithFilenameExtension:@"png"]];
	NSImage* plain = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect){
		[live drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
		return YES;
	}];
	OAK_ASSERT(![Pixels(DeletedReference(@"photo.png").image) isEqualToData:Pixels(plain)]);
}
