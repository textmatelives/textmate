#include <selection/selection.h>

static std::string const kMarker = "‸"; // U+2038, three bytes in UTF-8

static ng::ranges_t parse_markers (std::string& text)
{
	ng::ranges_t res;
	std::vector<size_t> marks;
	for(size_t pos = 0; (pos = text.find(kMarker, pos)) != std::string::npos; )
	{
		marks.push_back(pos);
		text.replace(pos, kMarker.size(), "");
	}
	for(size_t i = 0; i + 1 < marks.size(); i += 2)
		res.push_back(ng::range_t(ng::index_t(marks[i]), ng::index_t(marks[i+1])));
	if(marks.size() % 2 == 1)
		res.push_back(ng::range_t(ng::index_t(marks.back())));
	return res;
}

static std::string render_markers (std::string text, ng::ranges_t const& ranges)
{
	std::vector<size_t> marks;
	for(auto const& range : ranges)
	{
		marks.push_back(range.min().index);
		marks.push_back(range.max().index);
	}
	std::sort(marks.begin(), marks.end(), std::greater<size_t>());
	for(size_t pos : marks)
		text.insert(pos, kMarker);
	return text;
}

static std::pair<std::string, ng::occurrence_session_t> run_word_steps (std::string text, size_t n, bool ignore_case = true)
{
	ng::buffer_t buffer;
	ng::ranges_t ranges = parse_markers(text);
	buffer.insert(0, text);

	ng::occurrence_session_t session;
	for(size_t i = 0; i < n; ++i)
		std::tie(ranges, session) = ng::select_word_step(buffer, ranges, session, ignore_case);
	return { render_markers(text, ranges), session };
}

static std::pair<std::string, ng::occurrence_session_t> run_drop_step (std::string text, ng::occurrence_session_t const& session)
{
	ng::buffer_t buffer;
	ng::ranges_t ranges = parse_markers(text);
	buffer.insert(0, text);

	ng::ranges_t res;
	ng::occurrence_session_t next;
	std::tie(res, next) = ng::deselect_last_step(ranges, session);
	return { render_markers(text, res), next };
}

void test_caret_seed_adds_whole_words ()
{
	// Caret seeds the word and arms whole-word mode: the id inside
	// identifier is never added; the third press finds nothing new.
	OAK_ASSERT_EQ(run_word_steps("‸id identifier id", 1).first, "‸id‸ identifier id");
	OAK_ASSERT_EQ(run_word_steps("‸id identifier id", 2).first, "‸id‸ identifier ‸id‸");
	OAK_ASSERT_EQ(run_word_steps("‸id identifier id", 3).first, "‸id‸ identifier ‸id‸");
}

void test_hand_selection_adds_literally ()
{
	// A hand-made selection is honored as-is, subwords included.
	OAK_ASSERT_EQ(run_word_steps("‸id‸ identifier id", 1).first, "‸id‸ ‸id‸entifier id");
	OAK_ASSERT_EQ(run_word_steps("‸id‸ identifier id", 2).first, "‸id‸ ‸id‸entifier ‸id‸");
}

void test_drop_skips_next_add ()
{
	// Drop the last hit; the next add skips it instead of re-grabbing it.
	auto [marked, session] = run_word_steps("‸id id id", 3);
	OAK_ASSERT_EQ(marked, "‸id‸ ‸id‸ ‸id‸");

	std::tie(marked, session) = run_drop_step(marked, session);
	OAK_ASSERT_EQ(marked, "‸id‸ ‸id‸ id");

	ng::buffer_t buffer;
	std::string text = marked;
	ng::ranges_t ranges = parse_markers(text);
	buffer.insert(0, text);
	std::tie(ranges, session) = ng::select_word_step(buffer, ranges, session, true);
	OAK_ASSERT_EQ(render_markers(text, ranges), "‸id‸ ‸id‸ id"); // 3rd hit NOT re-added
}

void test_double_drop_keeps_skip_one_shot ()
{
	// Each drop arms a skip for exactly one add: dropping twice, then
	// adding, skips the second drop and takes the next available hit.
	auto [marked, session] = run_word_steps("‸id id id", 3);
	std::tie(marked, session) = run_drop_step(marked, session);
	std::tie(marked, session) = run_drop_step(marked, session);
	OAK_ASSERT_EQ(marked, "‸id‸ id id");

	ng::buffer_t buffer;
	std::string text = marked;
	ng::ranges_t ranges = parse_markers(text);
	buffer.insert(0, text);
	std::tie(ranges, session) = ng::select_word_step(buffer, ranges, session, true);
	OAK_ASSERT_EQ(render_markers(text, ranges), "‸id‸ id ‸id‸");
}

void test_diverged_selections_disarm_session ()
{
	// A whole-word session followed by a foreign selection falls back to
	// literal matching: from the middle id, literal finds identifier's id
	// while whole-word would find nothing.
	ng::buffer_t buffer;
	buffer.insert(0, "id id identifier");

	ng::ranges_t ranges;
	ng::occurrence_session_t session;
	std::tie(ranges, session) = ng::select_word_step(buffer, ng::ranges_t(ng::range_t(ng::index_t(0))), session, true);
	OAK_ASSERT_EQ(render_markers("id id identifier", ranges), "‸id‸ id identifier");

	std::string hand = "id ‸id‸ identifier";
	ranges = parse_markers(hand);
	std::tie(ranges, session) = ng::select_word_step(buffer, ranges, session, true);
	OAK_ASSERT_EQ(render_markers("id id identifier", ranges), "id ‸id‸ ‸id‸entifier");
}

void test_occurrence_case_sensitivity ()
{
	OAK_ASSERT_EQ(run_word_steps("‸ID id", 2, false).first, "‸ID‸ id");
	OAK_ASSERT_EQ(run_word_steps("‸ID id", 2, true).first, "‸ID‸ ‸id‸");
}

void test_multicaret_seeds_each_word ()
{
	ng::buffer_t buffer;
	buffer.insert(0, "id id");
	ng::ranges_t carets;
	carets.push_back(ng::range_t(ng::index_t(0)));
	carets.push_back(ng::range_t(ng::index_t(3)));

	ng::occurrence_session_t session;
	ng::ranges_t res;
	std::tie(res, session) = ng::select_word_step(buffer, carets, session, true);
	OAK_ASSERT_EQ(render_markers("id id", res), "‸id‸ ‸id‸");
}

void test_drop_outside_session_arms_no_skip ()
{
	// Without a live session the drop is plain: the next add re-grabs.
	ng::occurrence_session_t session;
	auto [marked, dropped] = run_drop_step("‸id‸ ‸id‸", session);
	OAK_ASSERT_EQ(marked, "‸id‸ id");
	OAK_ASSERT(dropped.armed == false);

	ng::buffer_t buffer;
	std::string text = marked;
	ng::ranges_t ranges = parse_markers(text);
	buffer.insert(0, text);
	std::tie(ranges, dropped) = ng::select_word_step(buffer, ranges, dropped, true);
	OAK_ASSERT_EQ(render_markers(text, ranges), "‸id‸ ‸id‸");
}
