#import "OakLocalLinkPolicy.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <text/encode.h>

static BOOL web_view_can_render (NSString* path)
{
	UTType* type = [UTType typeWithFilenameExtension:path.pathExtension];
	for(UTType* renderable in @[ UTTypeHTML, UTTypeImage, UTTypePDF ])
	{
		if([type conformsToType:renderable])
			return YES;
	}
	return NO;
}

OakLocalLinkAction OakLocalLinkActionForURL (NSURL* url, BOOL linkActivated, NSString* documentPath)
{
	if(!linkActivated || ![@[ @"tm-file", @"file" ] containsObject:url.scheme])
		return OakLocalLinkActionLoad;

	NSString* path = url.path;
	if(documentPath && url.fragment && [path isEqualToString:documentPath])
		return OakLocalLinkActionScroll;

	BOOL isDirectory = NO;
	if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory)
		return OakLocalLinkActionLoad;

	return web_view_can_render(path) ? OakLocalLinkActionLoad : OakLocalLinkActionOpen;
}

NSURL* OakTxMtOpenURLForPath (NSString* path)
{
	std::string encoded = encode::url_part(path.UTF8String, "/");
	return [NSURL URLWithString:[NSString stringWithFormat:@"txmt://open?url=file://%s", encoded.c_str()]];
}

NSString* OakScrollToFragmentScript (NSString* fragment)
{
	NSData* quoted = [NSJSONSerialization dataWithJSONObject:fragment options:NSJSONWritingFragmentsAllowed error:nil];
	return [NSString stringWithFormat:@"location.hash = %@", [[NSString alloc] initWithData:quoted encoding:NSUTF8StringEncoding]];
}
