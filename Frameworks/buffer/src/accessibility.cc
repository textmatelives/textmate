#include "meta_data.h"
#include <bundles/bundles.h>
#include <ns/language.h>
#include <text/trim.h>
#include <oak/oak.h>

namespace
{
	// A setting is either a string or, for text shown to the user, a dictionary
	// of strings keyed by language tag.
	std::string string_setting (plist::any_t const& value)
	{
		if(std::string const* str = plist::get<std::string>(&value))
			return *str;

		if(plist::dictionary_t const* dict = plist::get<plist::dictionary_t>(&value))
		{
			std::vector<std::string> tags;
			for(auto const& pair : *dict)
				tags.push_back(pair.first);

			auto it = dict->find(ns::preferred_localization(tags));
			if(std::string const* str = it != dict->end() ? plist::get<std::string>(&it->second) : nullptr)
				return *str;
		}
		return std::string();
	}

	std::shared_ptr<ng::symbol_transform_t> transform_setting (plist::any_t const& value)
	{
		std::string const src = string_setting(value);
		return src.empty() ? nullptr : std::make_shared<ng::symbol_transform_t>(src);
	}
}

namespace ng
{
	accessibility_t::accessibility_t ()
	{
		bundles::add_callback(this);
	}

	accessibility_t::~accessibility_t ()
	{
		bundles::remove_callback(this);
	}

	// ===========================
	// = Settings for each scope =
	// ===========================

	accessibility_t::rule_t const& accessibility_t::rule_for (scope::scope_t const& scope)
	{
		auto it = _rules.find(scope);
		if(it != _rules.end())
			return it->second;

		rule_t rule;
		rule.rotor = text::trim(string_setting(bundles::value_for_setting("accessibilityRotor", scope)));
		if(!rule.rotor.empty())
		{
			rule.rotor_transform = transform_setting(bundles::value_for_setting("accessibilityRotorTransformation", scope));

			std::string const extent = string_setting(bundles::value_for_setting("accessibilityRotorExtent", scope));
			rule.extent = extent == "line" ? extent_t::line : extent == "block" ? extent_t::block : extent_t::run;

			bundles::item_ptr orderItem;
			plist::any_t const order = bundles::value_for_setting("accessibilityRotorOrder", scope, &orderItem);
			if(orderItem)
				rule.order = atof(plist::convert<std::string>(order).c_str());
		}

		return _rules.emplace(scope, rule).first->second;
	}

	// =================
	// = Invalidation =
	// =================

	void accessibility_t::invalidate (size_t from, size_t to)
	{
		_dirty_from = std::min(_dirty_from, from);
		_dirty_to   = std::max(_dirty_to, to);
		_cached     = false;
		++_generation;
	}

	void accessibility_t::replace (buffer_t* buffer, size_t from, size_t to, size_t len)
	{
		_rotor_items.replace(from, to, len);

		if(_dirty_from < _dirty_to)
		{
			ssize_t const delta = len - (to - from);
			if(_dirty_from > to)
				_dirty_from += delta;
			else if(_dirty_from > from)
				_dirty_from = from;
			if(_dirty_to > to)
				_dirty_to += delta;
			else if(_dirty_to > from)
				_dirty_to = from + len;
		}
		invalidate(from, from + len);
	}

	void accessibility_t::did_parse (buffer_t const* buffer, size_t from, size_t to)
	{
		invalidate(from, to);
	}

	void accessibility_t::bundles_did_change ()
	{
		_rules.clear();
		invalidate(0, SIZE_T_MAX);
	}

	// ========================
	// = Rotor items, on demand =
	// ========================

	void accessibility_t::update_items (buffer_t const* buffer)
	{
		size_t from = std::min(_dirty_from, buffer->size());
		size_t to   = std::min(_dirty_to, buffer->size());

		// An item straddling the range is rebuilt whole.
		auto const widen = [&](auto const& tree){
			auto first = tree.upper_bound(from);
			if(first != tree.begin())
				from = std::min<size_t>(from, (--first)->first);
			auto last = tree.upper_bound(to);
			if(last != tree.begin())
				to = std::max<size_t>(to, (--last)->first + (*last).second.length);
		};
		widen(_rotor_items);
		to = std::min(to, buffer->size());

		_rotor_items.remove(_rotor_items.lower_bound(from), _rotor_items.lower_bound(to));

		auto const lineOf = [&](size_t i){ return buffer->substr(buffer->begin(buffer->convert(i).line), buffer->eol(buffer->convert(i).line)); };

		rule_t const* rotorRule = nullptr;
		size_t rotorFrom = 0;

		auto const endRotorItem = [&](size_t last){
			std::string const text = rotorRule->extent == extent_t::run ? buffer->substr(rotorFrom, last) : lineOf(rotorFrom);
			std::string const label = text::trim(rotorRule->rotor_transform ? rotorRule->rotor_transform->expand(text) : text);
			_rotor_items.set(rotorFrom, rotor_entry_t{ last - rotorFrom, rotorRule->rotor, label, rotorRule->extent });
			rotorRule = nullptr;
		};

		auto it = buffer->_scopes.upper_bound(from);
		if(it != buffer->_scopes.begin())
			--it;
		for(; it != buffer->_scopes.end() && it->first < (ssize_t)to; ++it)
		{
			size_t const i = std::max<ssize_t>(it->first, from);
			if(i >= to)
				break;

			rule_t const& rule = rule_for(it->second);

			if(rotorRule && (rule.rotor.empty() || rotorRule != &rule))
				endRotorItem(i);
			if(!rotorRule && !rule.rotor.empty())
			{
				rotorRule = &rule;
				rotorFrom = i;
			}
		}

		if(rotorRule && rotorFrom < to)
			endRotorItem(to);

		_dirty_from = SIZE_T_MAX;
		_dirty_to   = 0;
	}

	void accessibility_t::update (buffer_t const* buffer)
	{
		if(_dirty_from < _dirty_to)
			update_items(buffer);


		if(_cached)
			return;

		std::map<std::string, double> orders;
		for(auto const& pair : _rotor_items)
			orders.emplace(pair.second.rotor, 100);
		for(auto const& pair : _rules)
		{
			auto order = orders.find(pair.second.rotor);
			if(order != orders.end())
				order->second = std::min(order->second, pair.second.order);
		}
		_rotors_cache.clear();
		for(auto const& pair : orders)
			_rotors_cache.push_back({ pair.first, pair.second });
		std::stable_sort(_rotors_cache.begin(), _rotors_cache.end(), [](rotor_t const& lhs, rotor_t const& rhs){ return lhs.order < rhs.order; });

		_rotor_items_cache.clear();
		_cached = true;
	}

	std::vector<accessibility_t::rotor_t> const& accessibility_t::rotors (buffer_t const* buffer)
	{
		update(buffer);
		return _rotors_cache;
	}

	// Items with a line extent are one per line, those with a block extent join
	// with the item on the line before.
	std::vector<accessibility_t::rotor_item_t> const& accessibility_t::rotor_items (buffer_t const* buffer, std::string const& rotor)
	{
		update(buffer);
		auto cached = _rotor_items_cache.find(rotor);
		if(cached != _rotor_items_cache.end())
			return cached->second;

		std::vector<rotor_item_t>& res = _rotor_items_cache[rotor];
		size_t lastLine = SIZE_T_MAX;
		for(auto const& pair : _rotor_items)
		{
			if(pair.second.rotor != rotor)
				continue;

			size_t const first = pair.first, last = first + pair.second.length;
			size_t const line = buffer->convert(first).line;
			size_t const endLine = last > first ? buffer->convert(last - 1).line : line;
			if(pair.second.extent == extent_t::line && !res.empty() && line == lastLine)
				continue;
			if(pair.second.extent == extent_t::block && !res.empty() && lastLine != SIZE_T_MAX && line <= lastLine + 1)
			{
				res.back().last = std::max(res.back().last, last);
				lastLine = std::max(lastLine, endLine);
				continue;
			}
			res.push_back({ first, last, pair.second.label });
			lastLine = endLine;
		}
		return res;
	}

} /* ng */
