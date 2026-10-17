#import "quicklook.h"
#import <OSAKit/OSAKit.h>
#import <buffer/buffer.h>
#import <bundles/bundles.h>
#import <bundles/load.h>
#import <file/bytes.h>
#import <file/type.h>
#import <file/reader.h>
#import <io/path.h>
#import <cf/cf.h>
#import <ns/ns.h>
#import <plist/fs_cache.h>
#import <scope/scope.h>
#import <theme/theme.h>
#import <OakFoundation/NSString Additions.h>

namespace quicklook
{
	void setup (std::string const& bundles_path)
	{
		plist::cache_t cache; // no on-disk cache: the snapshot is small, scan it every launch
		auto index = create_bundle_index(std::vector<std::string>(1, bundles_path), cache);
		bundles::set_index(index.first, index.second);
	}

	NSAttributedString* render_file (std::string const& file_path, std::string const& theme_uuid, std::string const& font_name, double font_size, size_t max_bytes, size_t max_lines, std::string* file_type_out)
	{
		std::string fileContents = NULL_STR;
		if(path::extension(file_path) == ".scpt")
		{
			@autoreleasepool {
				NSDictionary* err = nil;
				if(OSAScript* script = [[OSAScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[NSString stringWithCxxString:file_path]] error:&err])
				{
					fileContents = [[script source] UTF8String] ?: NULL_STR;
					std::replace(fileContents.begin(), fileContents.end(), '\r', '\n');
				}
			}
		}

		if(fileContents == NULL_STR)
			fileContents = file::read_utf8(file_path, nullptr, max_bytes);

		if(max_lines != SIZE_T_MAX)
			fileContents.erase(std::find_if(fileContents.begin(), fileContents.end(), [&max_lines](char ch){ return ch == '\n' && --max_lines == 0; }), fileContents.end());

		ng::buffer_t buffer;
		buffer.insert(0, fileContents);

		// Apply appropriate grammar
		// NOTE: file::type() consults user settings first, which requires the
		// process environment (home folder lookup pops a modal alert when it
		// fails, hanging a sandboxed extension with no UI). A Quick Look
		// preview has no user settings, so query the grammar index directly.
		auto ql_bytes = std::make_shared<io::bytes_t>(fileContents.data(), fileContents.size(), false);
		std::string fileType = file::type_from_bytes(ql_bytes);
		if(fileType == NULL_STR)
			fileType = file::type_from_path(file_path);
		if(fileType == NULL_STR && path::extension(file_path).empty())
			fileType = "text.plain";
		if(fileType != NULL_STR)
		{
			for(auto item : bundles::query(bundles::kFieldGrammarScope, fileType, scope::wildcard, bundles::kItemTypeGrammar))
			{
				buffer.set_grammar(item);
				break;
			}
		}
		if(file_type_out)
			*file_type_out = fileType;

		if(theme_uuid == NULL_STR || font_name == NULL_STR || font_size == 0)
			return nil;

		bundles::item_ptr themeItem = bundles::lookup(theme_uuid);
		if(!themeItem)
			return nil;

		theme_ptr theme = parse_theme(themeItem);
		if(!theme)
			return nil;

		theme = theme->copy_with_font_name_and_size(font_name, font_size);

		// Perform syntax highlighting
		buffer.wait_for_repair();
		std::map<size_t, scope::scope_t> scopes = buffer.scopes(0, buffer.size());

		// Construct output
		NSMutableAttributedString* output = (__bridge_transfer NSMutableAttributedString*)CFAttributedStringCreateMutable(kCFAllocatorDefault, buffer.size());
		size_t from = 0;
		for(auto pair = scopes.begin(); pair != scopes.end(); )
		{
			styles_t styles = theme->styles_for_scope(pair->second);

			size_t to = ++pair != scopes.end() ? pair->first : buffer.size();

			[output appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:buffer.substr(from, to)] attributes:@{
				NSForegroundColorAttributeName:    [NSColor colorWithCGColor:styles.foreground()],
				NSBackgroundColorAttributeName:    [NSColor colorWithCGColor:styles.background()],
				NSFontAttributeName:               (__bridge NSFont*)styles.font(),
				NSUnderlineStyleAttributeName:     @(styles.underlined() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
				NSStrikethroughStyleAttributeName: @(styles.strikethrough() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
			}]];

			from = to;
		}

		return output;
	}
} /* quicklook */
