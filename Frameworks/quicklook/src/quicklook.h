#ifndef QUICKLOOK_H_V9X4K2P1
#define QUICKLOOK_H_V9X4K2P1

#import <Foundation/Foundation.h>
#import <string>

namespace quicklook
{
	// Index the bundles found directly under <bundles_path> (a directory of *.tmbundle).
	// Call once before render_file; later calls replace the index. No user files are touched.
	void setup (std::string const& bundles_path);

	// Highlight file_path with the given theme. Returns nil when the theme cannot be
	// resolved. file_type_out (when given) receives the detected scope, or NULL_STR when
	// the type is unknown — the caller decides the fallback (e.g. plain text).
	NSAttributedString* render_file (std::string const& file_path, std::string const& theme_uuid, std::string const& font_name, double font_size, size_t max_bytes = 20480, size_t max_lines = SIZE_T_MAX, std::string* file_type_out = nullptr);
} /* quicklook */

#endif /* end of include guard: QUICKLOOK_H_V9X4K2P1 */
