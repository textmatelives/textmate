#include <command/parser.h>

static bundle_command_t command (std::string const& scope, input::type input, input::type fallback = input::entire_document)
{
	bundle_command_t res;
	res.scope_selector = scope;
	res.input          = input;
	res.input_fallback = fallback;
	return res;
}

void test_whole_document_commands_accept_matching_files ()
{
	OAK_ASSERT(command_accepts_document(command("text.html.markdown", input::entire_document), "text.html.markdown"));
	OAK_ASSERT(command_accepts_document(command("text.html.markdown", input::entire_document), "text.html.markdown.gfm"));
	OAK_ASSERT(command_accepts_document(command("text.html.markdown", input::selection, input::entire_document), "text.html.markdown"));
	OAK_ASSERT(command_accepts_document(command("", input::entire_document), "source.ruby"));
}

void test_other_commands_and_files_are_rejected ()
{
	OAK_ASSERT(!command_accepts_document(command("text.html.markdown", input::entire_document), "source.ruby"));
	OAK_ASSERT(!command_accepts_document(command("text.html.markdown", input::selection, input::line), "text.html.markdown"));
	OAK_ASSERT(!command_accepts_document(command("text.html.markdown", input::entire_document), NULL_STR));
}
