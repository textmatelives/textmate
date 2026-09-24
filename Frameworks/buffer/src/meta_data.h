#ifndef BUFFER_META_DATA_H_Z0JQSBGY
#define BUFFER_META_DATA_H_Z0JQSBGY

#include "buffer.h"
#include "symbol_transform.h"
#include <ns/language.h>

namespace ng
{
	struct spelling_t : meta_data_t
	{
		bool disabled () const        { return _disabled; }
		void set_disabled (bool flag) { _disabled = flag; }

		void check_spelling (buffer_t const* buffer);
		std::map<size_t, bool> misspellings (buffer_t const* buffer, size_t from, size_t to) const;

		bool misspelled_at (size_t i) const;
		std::pair<size_t, size_t> next_misspelling (size_t from) const;
		void recheck (buffer_t const* buffer, size_t from, size_t to);

	private:
		void replace (buffer_t* buffer, size_t from, size_t to, size_t len);
		void did_parse (buffer_t const* buffer, size_t from, size_t to);

		typedef indexed_map_t<bool> tree_t;
		tree_t _misspellings;    // true = misspelled, false = proper
		bool _disabled = false;
	};

	struct symbols_t : meta_data_t
	{
		std::map<size_t, std::string> symbols (buffer_t const* buffer) const;
		std::string symbol_at (buffer_t const* buffer, size_t i) const;

	private:
		void replace (buffer_t* buffer, size_t from, size_t to, size_t len);
		void did_parse (buffer_t const* buffer, size_t from, size_t to);

		typedef indexed_map_t<std::string> tree_t;
		tree_t _symbols;
	};

	// What assistive clients are told about the text, from scope settings such
	// as ‘accessibilityRotor’ and ‘accessibilityLanguage’, the way ‘showInSymbolList’
	// works. Nothing is computed until asked for: edits and parsing only widen the
	// range the next query updates.
	struct accessibility_t : meta_data_t, bundles::callback_t
	{
		accessibility_t ();
		~accessibility_t ();

		enum class extent_t { run, line, block };

		struct rotor_t      { std::string name; double order; };
		struct rotor_item_t { size_t first, last; std::string label; };

		size_t generation () const { return _generation; } // changes when rotor items may have
		std::vector<rotor_t> const& rotors (buffer_t const* buffer);
		std::vector<rotor_item_t> const& rotor_items (buffer_t const* buffer, std::string const& rotor);
		std::vector<ns::language_run_t> languages (buffer_t const* buffer, size_t from, size_t to);

	private:
		void replace (buffer_t* buffer, size_t from, size_t to, size_t len);
		void did_parse (buffer_t const* buffer, size_t from, size_t to);
		void bundles_did_change ();

		struct rule_t
		{
			std::string language;
			std::string rotor;
			std::shared_ptr<symbol_transform_t> rotor_transform;
			extent_t extent = extent_t::run;
			double order = 100;
		};

		struct rotor_entry_t { size_t length; std::string rotor, label; extent_t extent; };

		rule_t const& rule_for (scope::scope_t const& scope);
		void update (buffer_t const* buffer);
		void update_items (buffer_t const* buffer);
		void invalidate (size_t from, size_t to);
		typedef std::shared_ptr<std::vector<ns::language_run_t>> language_runs_ptr;
		language_runs_ptr languages_for_line (buffer_t const* buffer, size_t n);

		std::map<scope::scope_t, rule_t> _rules;
		indexed_map_t<rotor_entry_t> _rotor_items;
		indexed_map_t<language_runs_ptr> _languages; // per line, offsets relative to the line
		size_t _dirty_from = 0, _dirty_to = SIZE_T_MAX;
		size_t _generation = 0;

		bool _cached = false;
		std::vector<rotor_t> _rotors_cache;
		std::map<std::string, std::vector<rotor_item_t>> _rotor_items_cache;
	};

	struct marks_t : meta_data_t
	{
		void set (size_t index, std::string const& markType, std::string const& value);
		void remove (size_t index, std::string const& markType);
		void remove_all (std::string const& markType);
		std::string get (size_t index, std::string const& markType) const;
		std::multimap<size_t, std::pair<std::string, std::string>> get_range (size_t from, size_t to) const;
		std::map<size_t, std::string> get_range (size_t from, size_t to, std::string const& markType) const;

		std::pair<size_t, std::string> next (size_t index, std::string const& markType) const;
		std::pair<size_t, std::string> prev (size_t index, std::string const& markType) const;

	private:
		void replace (buffer_t* buffer, size_t from, size_t to, size_t len);
		using meta_data_t::did_parse;

		typedef indexed_map_t<std::string> tree_t;
		std::map<std::string, tree_t> _marks;
	};

} /* ng */

#endif /* end of include guard: BUFFER_META_DATA_H_Z0JQSBGY */
