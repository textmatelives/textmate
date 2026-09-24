#ifndef BUFFER_SYMBOL_TRANSFORM_H_5E0R3ZQK
#define BUFFER_SYMBOL_TRANSFORM_H_5E0R3ZQK

#include <regexp/regexp.h>
#include <regexp/format_string.h>

namespace ng
{
	// A compiled ‘symbolTransformation’: a list of s/regexp/format/ rules, applied
	// in order to the text of a symbol. Compile once per scope, expand per symbol.
	struct symbol_transform_t
	{
		symbol_transform_t (std::string const& src);
		std::string expand (std::string const& str) const;

	private:
		struct record_t
		{
			regexp::pattern_t regexp;
			format_string::format_string_t format;
			bool repeat;
		};

		std::string src;
		std::vector<record_t> records;
	};

} /* ng */

#endif /* end of include guard: BUFFER_SYMBOL_TRANSFORM_H_5E0R3ZQK */
