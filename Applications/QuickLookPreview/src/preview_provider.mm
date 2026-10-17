#import <QuickLookUI/QuickLookUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <quicklook/quicklook.h>
#import <ns/ns.h>
#import <theme/theme.h>
#import <OakFoundation/NSString Additions.h>

// Undead (dark) lives in the vendored snapshot; MacClassic is kMacClassicThemeUUID.
static char const* kUndeadThemeUUID = "B41A92B1-CF6D-4F7B-BABA-18600C5C193B";

@interface TMQuickLookPreviewProvider : QLPreviewProvider <QLPreviewingController>
@end

static NSString* QLHexString (NSColor* color)
{
	NSColor* rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
	return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(rgb.redComponent * 255), (int)(rgb.greenComponent * 255), (int)(rgb.blueComponent * 255)];
}

@implementation TMQuickLookPreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest*)request completionHandler:(void (^)(QLPreviewReply* _Nullable, NSError* _Nullable))handler
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle* bundle = [NSBundle bundleForClass:[self class]];
		NSString* bundlesPath = [[bundle resourcePath] stringByAppendingPathComponent:@"Bundles"];
		quicklook::setup([bundlesPath fileSystemRepresentation]);
	});

	std::string path = [[[request fileURL] path] fileSystemRepresentation];

	// No NSApp in an extension: read the system-wide appearance default directly.
	// No NSApp in an extension: read the system-wide appearance default directly.
	BOOL darkMode = [[[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"] isEqualToString:@"Dark"];
	std::string themeUUID = darkMode ? kUndeadThemeUUID : kMacClassicThemeUUID;

	NSFont* font = [NSFont userFixedPitchFontOfSize:0];
	std::string fileType;
	NSAttributedString* output = quicklook::render_file(path, themeUUID, to_s([font fontName]), [font pointSize], 20480, SIZE_T_MAX, &fileType);

	if(!output || fileType == NULL_STR)
	{
		// We don't know the type, hand the raw bytes to the system as plain text
		NSData* data = [NSData dataWithContentsOfURL:[request fileURL]];
		QLPreviewReply* reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypePlainText contentSize:CGSizeMake(800, 600) dataCreationBlock:^NSData* (QLPreviewReply* reply, NSError** error){
			return data;
		}];
		handler(reply, nil);
		return;
	}

	NSColor* background = [NSColor whiteColor];
	if([output length] > 0)
	{
		NSColor* firstRun = [output attributesAtIndex:0 effectiveRange:NULL][NSBackgroundColorAttributeName];
		if([firstRun isKindOfClass:[NSColor class]])
			background = firstRun;
	}

	// Quick Look's Spacebar RTF renderer forces the system background; HTML
	// honors author colors, so emit styled HTML to preserve the theme.
	NSFontManager* fontManager = [NSFontManager sharedFontManager];
	NSMutableString* html = [NSMutableString stringWithFormat:@"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>html,body{margin:0;padding:8px;background:%@;}pre{margin:0;font-family:'%@',monospace;font-size:%.0fpx;line-height:1.35;}</style></head><body><pre>", QLHexString(background), [font fontName], [font pointSize]];
	[output enumerateAttributesInRange:NSMakeRange(0, [output length]) options:0 usingBlock:^(NSDictionary* attrs, NSRange range, BOOL* stop){
		NSString* text = [[[output string] substringWithRange:range] stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
		text = [text stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
		text = [text stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
		NSMutableString* style = [NSMutableString string];
		if(NSColor* fg = attrs[NSForegroundColorAttributeName])
			[style appendFormat:@"color:%@;", QLHexString(fg)];
		if(NSColor* bg = attrs[NSBackgroundColorAttributeName])
			[style appendFormat:@"background-color:%@;", QLHexString(bg)];
		if(NSFont* runFont = attrs[NSFontAttributeName])
		{
			NSFontTraitMask traits = [fontManager traitsOfFont:runFont];
			if(traits & NSBoldFontMask)
				[style appendString:@"font-weight:bold;"];
			if(traits & NSItalicFontMask)
				[style appendString:@"font-style:italic;"];
		}
		NSMutableArray* decorations = [NSMutableArray array];
		if([attrs[NSUnderlineStyleAttributeName] intValue] != NSUnderlineStyleNone)
			[decorations addObject:@"underline"];
		if([attrs[NSStrikethroughStyleAttributeName] intValue] != NSUnderlineStyleNone)
			[decorations addObject:@"line-through"];
		if([decorations count] > 0)
			[style appendFormat:@"text-decoration:%@;", [decorations componentsJoinedByString:@" "]];
		if([style length] > 0)
			[html appendFormat:@"<span style=\"%@\">%@</span>", style, text];
		else	[html appendString:text];
	}];
	[html appendString:@"</pre></body></html>"];
	NSData* htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];

	// Measure the laid-out height at a fixed preview width
	NSTextStorage* storage = [[NSTextStorage alloc] initWithAttributedString:output];
	NSLayoutManager* layout = [[NSLayoutManager alloc] init];
	NSTextContainer* container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(800, CGFLOAT_MAX)];
	[layout addTextContainer:container];
	[storage addLayoutManager:layout];
	[layout glyphRangeForTextContainer:container];
	CGFloat height = MAX(NSHeight([layout usedRectForTextContainer:container]), 100);

	QLPreviewReply* reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypeHTML contentSize:CGSizeMake(800, height) dataCreationBlock:^NSData* (QLPreviewReply* reply, NSError** error){
		return htmlData;
	}];
	handler(reply, nil);
}

@end
