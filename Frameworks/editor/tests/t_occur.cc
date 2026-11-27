#include <editor/editor.h>

static std::string show_ranges (ng::buffer_t const& buf, ng::ranges_t const& ranges)
{
	std::string text = buf.substr(0, buf.size());
	std::vector<size_t> marks;
	for(auto const& range : ranges)
	{
		marks.push_back(range.min().index);
		marks.push_back(range.max().index);
	}
	std::sort(marks.begin(), marks.end(), std::greater<size_t>());
	for(size_t pos : marks)
		text.insert(pos, "‸");
	return text;
}

void test_ctrl_w_add_and_drop_skip ()
{
	ng::buffer_t buf;
	ng::editor_t editor(buf);
	editor.insert("id id id");
	editor.perform(ng::kMoveToBeginningOfLine);

	editor.perform(ng::kSelectWord);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ id id");

	editor.perform(ng::kSelectWord);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ ‸id‸ id");

	editor.perform(ng::kSelectWord);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ ‸id‸ ‸id‸");

	editor.perform(ng::kDeselectLast);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ ‸id‸ id");

	editor.perform(ng::kSelectWord);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ ‸id‸ id"); // dropped hit skipped, not re-grabbed
}

void test_ctrl_w_seeds_whole_word_mode ()
{
	ng::buffer_t buf;
	ng::editor_t editor(buf);
	editor.insert("id identifier id");
	editor.perform(ng::kMoveToBeginningOfLine);

	editor.perform(ng::kSelectWord);
	editor.perform(ng::kSelectWord);
	OAK_ASSERT_EQ(show_ranges(buf, editor.ranges()), "‸id‸ identifier ‸id‸");
}
