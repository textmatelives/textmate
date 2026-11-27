#ifndef SELECTION_H_EKADE2RF
#define SELECTION_H_EKADE2RF

#include "types.h"
#include <regexp/find.h>
#include <text/types.h>
enum move_unit_type { kSelectionMoveLeft, kSelectionMoveRight, kSelectionMoveFreehandedLeft, kSelectionMoveFreehandedRight, kSelectionMoveUp, kSelectionMoveDown, kSelectionMoveToBeginOfSelection, kSelectionMoveToEndOfSelection, kSelectionMoveToBeginOfSubWord, kSelectionMoveToEndOfSubWord, kSelectionMoveToBeginOfWord, kSelectionMoveToEndOfWord, kSelectionMoveToBeginOfSoftLine, kSelectionMoveToEndOfSoftLine, kSelectionMoveToBeginOfIndentedLine, kSelectionMoveToEndOfIndentedLine, kSelectionMoveToBeginOfLine, kSelectionMoveToEndOfLine, kSelectionMoveToBeginOfParagraph, kSelectionMoveToEndOfParagraph, kSelectionMoveToBeginOfHardParagraph, kSelectionMoveToEndOfHardParagraph, kSelectionMoveToBeginOfTypingPair, kSelectionMoveToEndOfTypingPair, kSelectionMoveToBeginOfColumn, kSelectionMoveToEndOfColumn, kSelectionMovePageUp, kSelectionMovePageDown, kSelectionMoveToBeginOfDocument, kSelectionMoveToEndOfDocument, kSelectionMoveNowhere };
enum select_unit_type { kSelectionExtendLeft, kSelectionExtendRight, kSelectionExtendFreehandedLeft, kSelectionExtendFreehandedRight, kSelectionExtendUp, kSelectionExtendDown, kSelectionExtendToBeginOfSubWord, kSelectionExtendToEndOfSubWord, kSelectionExtendToBeginOfWord, kSelectionExtendToEndOfWord, kSelectionExtendToBeginOfSoftLine, kSelectionExtendToEndOfSoftLine, kSelectionExtendToBeginOfIndentedLine, kSelectionExtendToEndOfIndentedLine, kSelectionExtendToBeginOfLine, kSelectionExtendToEndOfLine, kSelectionExtendToBeginOfParagraph, kSelectionExtendToEndOfParagraph, kSelectionExtendToBeginOfTypingPair, kSelectionExtendToEndOfTypingPair, kSelectionExtendToBeginOfColumn, kSelectionExtendToEndOfColumn, kSelectionExtendPageUp, kSelectionExtendPageDown, kSelectionExtendToBeginOfDocument, kSelectionExtendToEndOfDocument, kSelectionExtendToWord, kSelectionExtendToWordOrTypingPair, kSelectionExtendToScope, kSelectionExtendToSoftLine, kSelectionExtendToLineExclLF, kSelectionExtendToLine, kSelectionExtendToParagraph, kSelectionExtendToTypingPair, kSelectionExtendToAll };

namespace scope { struct context_t; struct selector_t; }

namespace ng
{
	struct buffer_api_t;

	struct layout_movement_t
	{
		virtual ~layout_movement_t () = default;
		virtual index_t index_left_of (index_t const& index) const = 0;
		virtual index_t index_right_of (index_t const& index) const = 0;
		virtual index_t index_above (index_t const& index) const = 0;
		virtual index_t index_below (index_t const& index) const = 0;
		virtual index_t index_at_bol_for (index_t const& index) const = 0;
		virtual index_t index_at_eol_for (index_t const& index) const = 0;
		virtual index_t page_up_for (index_t const& index) const = 0;
		virtual index_t page_down_for (index_t const& index) const = 0;
		virtual size_t effective_wrap_column () const = 0;
	};

	ranges_t convert (buffer_api_t const& buffer, text::selection_t const& selection);
	ranges_t sanitize (buffer_api_t const& buffer, ranges_t const& selection);
	bool not_empty (buffer_api_t const& buffer, ranges_t const& selection);
	bool multiline (buffer_api_t const& buffer, ranges_t const& selection);
	ranges_t move (buffer_api_t const& buffer, ranges_t const& selection, move_unit_type const unit, layout_movement_t const* layout = NULL);
	ranges_t extend (buffer_api_t const& buffer, ranges_t const& selection, select_unit_type const unit, layout_movement_t const* layout = NULL);
	ranges_t extend_if_empty (buffer_api_t const& buffer, ranges_t const& selection, select_unit_type const unit, layout_movement_t const* layout = NULL);
	ranges_t select_scope (buffer_api_t const& buffer, ranges_t const& selection, scope::selector_t const& scopeSelector);
	ranges_t toggle_columnar (ranges_t const& selection);
	ranges_t deselect_last (ranges_t const& selection);

	// Word-occurrence multi-select (^W flow): a bare caret seeds the word
	// under it and arms whole-word mode; repeats add the next occurrence;
	// a hand-made selection adds literally. The session disarms itself when
	// the selections diverge from its snapshot, so no lifecycle hooks are
	// needed; a drop arms a one-shot skip of the dropped range.
	struct occurrence_session_t
	{
		bool armed = false;
		bool whole_words = false;
		ranges_t snapshot;
		bool has_skip = false;
		range_t skip;
	};

	std::pair<ranges_t, occurrence_session_t> select_word_step (buffer_api_t const& buffer, ranges_t const& selection, occurrence_session_t const& session, bool ignore_case, layout_movement_t const* layout = NULL);
	std::pair<ranges_t, occurrence_session_t> deselect_last_step (ranges_t const& selection, occurrence_session_t const& session);
	scope::context_t scope (buffer_api_t const& buffer, ranges_t const& selection, std::string const& extraAttributes = NULL_STR);
	ranges_t highlight_ranges_for_movement (buffer_api_t const& buffer, ranges_t const& oldSelection, ranges_t const& newSelection);
	std::map< range_t, std::map<std::string, std::string> > find (buffer_api_t const& buffer, ranges_t const& selection, std::string const& searchFor, find::options_t options, ranges_t const& searchRanges = ranges_t(), bool* didWrap = nullptr, index_t extend_after = index_t());
	std::map< range_t, std::map<std::string, std::string> > find_all (buffer_api_t const& buffer, std::string const& searchFor, find::options_t options, ranges_t const& searchRanges = ranges_t());
	range_t word_at (buffer_api_t const& buffer, range_t const& range);
	ranges_t all_words (buffer_api_t const& buffer);

	ranges_t dissect_columnar (buffer_api_t const& buffer, ranges_t const& selection);

	extern std::string const kCharacterClassWord;
	extern std::string const kCharacterClassSpace;
	extern std::string const kCharacterClassOther;
	extern std::string const kCharacterClassUnknown;

	std::string character_class (buffer_api_t const& buffer, size_t index);

	ranges_t from_string (buffer_api_t const& buffer, std::string const& str);
	std::string to_s (buffer_api_t const& buffer, ranges_t const& ranges);

} /* ng */

#endif /* end of include guard: SELECTION_H_EKADE2RF */
