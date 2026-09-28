#include "meta_data.h"
#include "symbol_transform.h"
#include <bundles/bundles.h>
#include <oak/oak.h>
#include <oak/duration.h>

namespace ng
{
	void symbols_t::replace (buffer_t* buffer, size_t from, size_t to, size_t len) { _symbols.replace(from, to, len); }

	void symbols_t::did_parse (buffer_t const* buffer, size_t from, size_t to)
	{
		_symbols.remove(_symbols.lower_bound(from), _symbols.lower_bound(to));

		std::set<scope::scope_t> all_scopes;
		foreach(it, buffer->_scopes.lower_bound(from), buffer->_scopes.lower_bound(to))
			all_scopes.insert(all_scopes.end(), it->second);

		std::map<scope::scope_t, symbol_transform_t> transforms;
		for(auto const& it : all_scopes)
		{
			if(plist::is_true(bundles::value_for_setting("showInSymbolList", it)))
			{
				plist::any_t const& symbolTransformationValue = bundles::value_for_setting("symbolTransformation", it);
				std::string const* symbolTransformation = plist::get<std::string>(&symbolTransformationValue);
				transforms.emplace(it, symbol_transform_t(symbolTransformation ? *symbolTransformation : ""));
			}
		}

		size_t beginOfSymbol = 0;
		bool inSymbol = false;
		symbol_transform_t* transform = nullptr;
		foreach(it, buffer->_scopes.lower_bound(from), buffer->_scopes.lower_bound(to))
		{
			std::map<scope::scope_t, symbol_transform_t>::iterator transformIt = transforms.find(it->second);
			if(transformIt != transforms.end())
			{
				if(!inSymbol)
					beginOfSymbol = it->first;
				transform = &transformIt->second;
				inSymbol  = true;
			}
			else if(inSymbol)
			{
				_symbols.set(beginOfSymbol, transform->expand(buffer->substr(beginOfSymbol, it->first)));
				inSymbol = false;
			}
		}

		if(inSymbol)
			_symbols.set(beginOfSymbol, transform->expand(buffer->substr(beginOfSymbol, to)));
	}

	std::map<size_t, std::string> symbols_t::symbols (buffer_t const* buffer) const
	{
		std::map<size_t, std::string> res;
		for(auto const& it : _symbols)
			res.insert(it);
		return res;
	}

	std::string symbols_t::symbol_at (buffer_t const* buffer, size_t i) const
	{
		tree_t::iterator it = _symbols.upper_bound(i);
		if(it == _symbols.begin())
			return NULL_STR;
		return (--it)->second;
	}

} /* ng */
