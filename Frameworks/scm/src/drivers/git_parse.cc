#include "git_parse.h"
#include <text/tokenize.h>

namespace scm { namespace git_parse {

	scm::status::type resolve_porcelain_xy (char X, char Y)
	{
		if(X == 'U' || Y == 'U' || (X == 'A' && Y == 'A') || (X == 'D' && Y == 'D'))
			return scm::status::conflicted;

		if(X == '?' && Y == '?')
			return scm::status::unversioned;
		if(X == '!' && Y == '!')
			return scm::status::ignored;

		switch(X)
		{
			case 'A': return scm::status::added;
			case 'D': return scm::status::deleted;
			case 'M':
			case 'T': return scm::status::modified;
			case 'R':
			case 'C': return scm::status::added;
		}

		switch(Y)
		{
			case 'M':
			case 'T': return scm::status::modified;
			case 'D': return scm::status::deleted;
			case 'A': return scm::status::added;
		}

		if(X == ' ' && Y == ' ')
			return scm::status::none;

		return scm::status::unknown;
	}

	void parse_porcelain (std::map<std::string, scm::status::type>& entries,
	                      std::string const& output)
	{
		if(output == NULL_STR)
			return;

		auto tokens = text::tokenize(output.begin(), output.end(), '\0');
		auto it = tokens.begin();
		auto end = tokens.end();
		while(it != end)
		{
			std::string entry = *it;
			if(entry.empty())
				break;
			++it;

			if(entry.size() < 4) // need at least "XY <one-char path>"
				continue;

			char X = entry[0];
			char Y = entry[1];
			std::string path = entry.substr(3); // skip "XY "

			std::string origPath;
			if(X == 'R' || X == 'C')
			{
				if(it == end)
					break;
				origPath = *it;
				++it;
			}

			scm::status::type status = resolve_porcelain_xy(X, Y);
			if(status != scm::status::none && status != scm::status::unknown)
				entries[path] = status;

			if(!origPath.empty())
				entries[origPath] = scm::status::deleted;
		}
	}

} /* git_parse */ } /* scm */
