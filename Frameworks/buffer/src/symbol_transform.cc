#include "symbol_transform.h"
#include <oak/oak.h>
#include <text/ctype.h>

namespace
{
	bool parse_char (char const*& it, char const* last, char ch)
	{
		return it != last && *it == ch ? (++it, true) : false;
	}
}

namespace ng
{
	symbol_transform_t::symbol_transform_t (std::string const& src) : src(src)
	{
		char const* it = src.data();
		char const* last = it + src.size();
		while(it != last)
		{
			if(text::is_space(*it) || *it == '\n')
			{
				++it;
			}
			else if(parse_char(it, last, '#'))
			{
				while(!parse_char(it, last, '\n') && it != last)
					++it;
			}
			else if(parse_char(it, last, 's') && parse_char(it, last, '/'))
			{
				std::string regexp;
				while(it != last && *it != '/')
				{
					if(*it == '\\' && it + 1 != last)
						regexp += *it++;
					regexp += *it++;
				}

				if(!parse_char(it, last, '/'))
				{
					os_log_error(OS_LOG_DEFAULT, "Malformed symbol transformation at offset %td (expected ‘/’): %{public}s", it - src.data(), src.c_str());
					return;
				}

				format_string::format_string_t format(std::string(it, last), "/");
				if(format.length() == 0)
				{
					os_log_error(OS_LOG_DEFAULT, "Malformed symbol transformation at offset %td (expected /format string/): %{public}s", it - src.data(), src.c_str());
					return;
				}

				it += format.length();

				std::string options;
				while(it != last && 'a' <= *it && *it <= 'z')
					options += *it++;

				parse_char(it, last, ';'); // semi-colon is optional, so we do not treat it as an error

				records.push_back((record_t){ regexp::pattern_t(regexp, options), format, options.find('g') != std::string::npos });
			}
			else
			{
				os_log_error(OS_LOG_DEFAULT, "Malformed symbol transformation at offset %td (expected ‘s’, ‘#’, or space, found %c (0x%02x)): %{public}s", it - src.data(), *it, *it, src.c_str());
				return;
			}
		}
	}

	std::string symbol_transform_t::expand (std::string const& str) const
	{
		static regexp::pattern_t newline("\n");
		std::string res = replace(str, newline, format_string::format_string_t(" "));
		for(auto const& it : records)
			res = replace(res, it.regexp, it.format, it.repeat);
		res = replace(res, newline, format_string::format_string_t("↵"));

		return res;
	}

} /* ng */
