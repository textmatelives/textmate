#include <bundles/bundles.h>
#include <test/bundle_index.h>
#include <test/jail.h>

void setup_fixtures ()
{
	static std::string BaseEnvironment =
		"{	name     = 'Base Environment';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'TEST'; value = 'foo'; },"
		"		);"
		"	};"
		"}";

	static std::string PathEnvironment =
		"{	name     = 'Path Environment';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'PATH'; value = '/usr/bin';                 },"
		"			{	name = 'PATH'; value = '$PATH:/bin';               },"
		"			{	name = 'PATH'; value = '$PATH:/tmp'; disabled = 1; },"
		"			{	name = 'PATH'; value = '$PATH:/sbin';              },"
		"		);"
		"	};"
		"}";

	static std::string TeXEnvironment =
		"{	name     = 'TeX Environment';"
		"	scope    = 'text.tex';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'PATH'; value = '$PATH:/usr/texbin'; },"
		"		);"
		"	};"
		"}";

	static std::string CxxEnvironment =
		"{	name     = 'C++ Environment';"
		"	scope    = 'source.c++';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'TEST'; value = '${TEST:+$TEST:}bar'; },"
		"		);"
		"	};"
		"}";

	static std::string DialogEnvironment =
		"{	name     = 'Dialog Environment';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'DialogPath'; value = '${TM_DIALOG_BUNDLE_SUPPORT:?$TM_DIALOG_BUNDLE_SUPPORT/bin:*** Dialog bundle missing ***}'; },"
		"		);"
		"	};"
		"	require = ("
		"		{ name = 'Dialog'; uuid = 'B0B94C92-1870-491C-A928-9528387EEACA'; },"
		"	);"
		"}";

	static std::string BaseCommentEnvironment =
		"{	name     = 'Base Environment';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'TM_COMMENT_START';    value = '/*';                   },"
		"			{	name = 'TM_COMMENT_STOP';     value = '*/';                   },"
		"			{	name = 'TM_COMMENT_START_2';  value = '//';                   },"
		"			{	name = 'TM_COMMENT_STYLE';    value = '$TM_BUNDLE_ITEM_NAME'; },"
		"		);"
		"	};"
		"}";

	static std::string RubyCommentEnvironment =
		"{	name     = 'Ruby Environment';"
		"	scope    = 'source.ruby';"
		"	settings = {"
		"		shellVariables = ("
		"			{	name = 'TM_COMMENT_START';    value = '# ';                   },"
		"			{	name = 'TM_COMMENT_START_2';  value = '==begin';              },"
		"			{	name = 'TM_COMMENT_STOP_2';   value = '==end';                },"
		"			{	name = 'TM_COMMENT_STYLE';    value = '$TM_BUNDLE_ITEM_NAME'; },"
		"		);"
		"	};"
		"}";

	static std::string BaseSnippet =
		"{	name          = 'Base Snippet';"
		"	keyEquivalent = '^p';"
		"	tabTrigger    = 'bla';"
		"	content       = 'foo';"
		"}";

	static std::string CxxSnippet =
		"{	name          = 'C++ Snippet';"
		"	keyEquivalent = '^p';"
		"	tabTrigger    = 'bla';"
		"	scope         = 'source.c++';"
		"	content       = 'bar';"
		"}";

	static std::string DisabledCxxSnippet =
		"{	name          = 'Disabled C++ Snippet';"
		"	keyEquivalent = '^p';"
		"	tabTrigger    = 'bla';"
		"	scope         = 'source.c++';"
		"	content       = 'bar';"
		"	isDisabled    = 1;"
		"}";

	static std::string TrueWithLocation =
		"{	name = 'TrueWithLocation';"
		"	requiredCommands = ("
		"		{	command = 'true';"
		"			locations = ( '/usr/bin/true' );"
		"		},"
		"	);"
		"}";

	static std::string TrueWithVariable =
		"{	name = 'TrueWithVariable';"
		"	requiredCommands = ("
		"		{	command = 'true';"
		"			variable = 'TM_TRUE';"
		"		},"
		"	);"
		"}";

	static std::string TrueWithLocationAndVariable =
		"{	name = 'TrueWithLocationAndVariable';"
		"	requiredCommands = ("
		"		{	command = 'true';"
		"			locations = ( '/usr/bin/true' );"
		"			variable = 'TM_TRUE';"
		"		},"
		"	);"
		"}";

	static std::string TrueWithBadLocation =
		"{	name = 'TrueWithBadLocation';"
		"	requiredCommands = ("
		"		{	command = 'true';"
		"			locations = ( '/foo/bar/true' );"
		"		},"
		"	);"
		"}";

	static std::string TrueWithBadLocationAndVariable =
		"{	name = 'TrueWithBadLocationAndVariable';"
		"	requiredCommands = ("
		"		{	command = 'true';"
		"			locations = ( '/foo/bar/true' );"
		"			variable = 'TM_TRUE';"
		"		},"
		"	);"
		"}";

	test::bundle_index_t bundleIndex;
	bundleIndex.add(bundles::kItemTypeSettings, BaseEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, BaseCommentEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, PathEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, DialogEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, TeXEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, CxxEnvironment);
	bundleIndex.add(bundles::kItemTypeSettings, RubyCommentEnvironment);
	bundleIndex.add(bundles::kItemTypeSnippet,  BaseSnippet);
	bundleIndex.add(bundles::kItemTypeSnippet,  CxxSnippet);
	bundleIndex.add(bundles::kItemTypeSnippet,  DisabledCxxSnippet);

	bundleIndex.add(bundles::kItemTypeCommand,  TrueWithLocation);
	bundleIndex.add(bundles::kItemTypeCommand,  TrueWithVariable);
	bundleIndex.add(bundles::kItemTypeCommand,  TrueWithLocationAndVariable);
	bundleIndex.add(bundles::kItemTypeCommand,  TrueWithBadLocation);
	bundleIndex.add(bundles::kItemTypeCommand,  TrueWithBadLocationAndVariable);

	bundles::item_ptr dialogBundle = bundleIndex.add(bundles::kItemTypeBundle, "{ name = 'Dialog'; uuid = 'B0B94C92-1870-491C-A928-9528387EEACA'; }");

	static test::jail_t jail;
	bundles::set_locations(std::vector<std::string>(1, jail.path()));
	dialogBundle->save();
	jail.mkdir("Bundles/Dialog.tmbundle/Support");

	bundleIndex.commit();
}

#define OAK_ASSERT_STR_EQ(lhs, rhs) do { std::string _lhs = (lhs); std::string _rhs = (rhs); if(!(_lhs == _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, "==", #rhs, to_s(_lhs), "!=", to_s(_rhs)), __FILE__, __LINE__); } while(false)

void test_environment_format_strings ()
{
	std::map<std::string, std::string> base;

	OAK_ASSERT_EQ(bundles::scope_variables(base, "")["TEST"],                        "foo");
	OAK_ASSERT_EQ(bundles::scope_variables(base, "source.c++")["TEST"],              "foo:bar");
	OAK_ASSERT_EQ(bundles::scope_variables(base, "source.any")["TM_COMMENT_STYLE"],  "Base Environment");
	OAK_ASSERT_EQ(bundles::scope_variables(base, "source.ruby")["TM_COMMENT_STYLE"], "Ruby Environment");

	OAK_ASSERT_EQ(bundles::scope_variables(base, "text.plain")["PATH"], "/usr/bin:/bin:/sbin");
	OAK_ASSERT_EQ(bundles::scope_variables(base, "text.tex").find("PATH")->second,   "/usr/bin:/bin:/sbin:/usr/texbin");
	OAK_ASSERT_EQ(bundles::scope_variables(base, "text.tex")["PATH"], "/usr/bin:/bin:/sbin:/usr/texbin");
}

void test_v1_variable_shadowing ()
{
	auto baseEnv = bundles::scope_variables(std::map<std::string, std::string>(), "");
	OAK_ASSERT_EQ(baseEnv["TM_COMMENT_START"],   "/*");
	OAK_ASSERT_EQ(baseEnv["TM_COMMENT_STOP"],    "*/");
	OAK_ASSERT_EQ(baseEnv["TM_COMMENT_START_2"], "//");
	OAK_ASSERT(baseEnv.find("TM_COMMENT_STOP_2") == baseEnv.end());

	std::map<std::string, std::string> rubyEnv = bundles::scope_variables(std::map<std::string, std::string>(), "source.ruby");
	OAK_ASSERT_EQ(rubyEnv["TM_COMMENT_START"],   "# ");
	OAK_ASSERT(rubyEnv.find("TM_COMMENT_STOP") == rubyEnv.end());
	OAK_ASSERT_EQ(rubyEnv["TM_COMMENT_START_2"], "==begin");
	OAK_ASSERT_EQ(rubyEnv["TM_COMMENT_STOP_2"],  "==end");
}

void test_scope_query ()
{
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldKeyEquivalent, "^p", "source.c++").size(), 1);
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldKeyEquivalent, "^p", "source.c++", bundles::kItemTypeMenuTypes, oak::uuid_t(), false).size(), 2);
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldKeyEquivalent, "^p", "source.c++", bundles::kItemTypeMenuTypes, oak::uuid_t(), false, true).size(), 3);

	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.any").size(), 1);
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.any").front()->name(), "Base Snippet");
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.c++").size(), 1);
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.c++").front()->name(), "C++ Snippet");

	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.c++", bundles::kItemTypeMenuTypes, oak::uuid_t(), false).size(), 2);
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.c++", bundles::kItemTypeMenuTypes, oak::uuid_t(), false).front()->name(), "C++ Snippet");
	OAK_ASSERT_EQ(bundles::query(bundles::kFieldTabTrigger, "bla", "source.c++", bundles::kItemTypeMenuTypes, oak::uuid_t(), false).back()->name(),  "Base Snippet");
}

void test_require ()
{
	std::string dialogPath = bundles::scope_variables(std::map<std::string, std::string>(), "text")["DialogPath"];
	std::string pathSuffix = "/Bundles/Dialog.tmbundle/Support/bin";
	OAK_ASSERT_EQ(dialogPath.find(pathSuffix) + pathSuffix.size(), dialogPath.size());
}

namespace
{
	std::string const BundleUUID = "B0B94C92-1870-491C-A928-9528387EEACA";
	std::string const MenuUUID   = "C1CA5D03-2981-402D-B039-A63949FBDA12";
	std::string const FirstUUID  = "D2DB6E14-3A92-513E-C14A-B74A5A0CCE20";
	std::string const SecondUUID = "E3EC7F25-4BA3-624F-D25B-C85B6B1DDF31";
	std::string const ThirdUUID  = "F4FD8036-5CB4-7350-E36C-D96C7C2EE042";

	plist::dictionary_t make_info_plist ()
	{
		return plist::dictionary_t{
			{ "mainMenu", plist::dictionary_t{
				{ "items", plist::array_t{ plist::any_t(FirstUUID), plist::any_t(SecondUUID) } },
				{ "submenus", plist::dictionary_t{
					{ MenuUUID, plist::dictionary_t{
						{ "name", plist::any_t("Extras") },
						{ "items", plist::array_t{ plist::any_t(FirstUUID) } },
					} },
				} },
			} },
		};
	}

	std::vector<std::string> items_at (plist::dictionary_t const& info, std::string const& keyPath)
	{
		plist::array_t items;
		if(!plist::get_key_path(info, keyPath, items))
			return std::vector<std::string>();
		std::vector<std::string> res;
		for(auto const& entry : items)
		{
			if(std::string const* str = plist::get<std::string>(&entry))
				res.push_back(*str);
		}
		return res;
	}
}

void test_insert_uuid_into_main_menu ()
{
	// Append to the top-level menu …
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, ThirdUUID));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 3);
		OAK_ASSERT_EQ(items[2], ThirdUUID);
	}

	// … or directly after the selected sibling.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, ThirdUUID, FirstUUID));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 3);
		OAK_ASSERT_EQ(items[0], FirstUUID);
		OAK_ASSERT_EQ(items[1], ThirdUUID);
		OAK_ASSERT_EQ(items[2], SecondUUID);
	}

	// Unknown sibling falls back to append; existing entries are not duplicated.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, ThirdUUID, MenuUUID));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").back(), ThirdUUID);

		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, FirstUUID));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 3);
	}

	// Submenu placement keeps the submenu’s name and other menus untouched.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, MenuUUID, SecondUUID, FirstUUID));
		auto items = items_at(info, "mainMenu.submenus." + MenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 2);
		OAK_ASSERT_EQ(items[0], FirstUUID);
		OAK_ASSERT_EQ(items[1], SecondUUID);
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 2);

		std::string name;
		OAK_ASSERT(plist::get_key_path(info, "mainMenu.submenus." + MenuUUID + ".name", name));
		OAK_ASSERT_EQ(name, "Extras");
	}

	// Unknown menus and malformed input fail without touching the plist.
	{
		plist::dictionary_t info = make_info_plist();
		plist::dictionary_t const original = info;
		OAK_ASSERT(!bundles::insert_uuid_into_main_menu(info, BundleUUID, ThirdUUID, SecondUUID));
		OAK_ASSERT(!bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, "not-a-uuid"));
		OAK_ASSERT(plist::equal(info, original));
	}

	// A bundle with no mainMenu at all (never explicitly ordered, e.g. fresh
	// leftovers) gets one, so a validated drop persists instead of failing
	// silently on the plist gate while the panes already accepted it.
	{
		plist::dictionary_t empty;
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(empty, BundleUUID, BundleUUID, ThirdUUID));
		auto items = items_at(empty, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 1);
		OAK_ASSERT_EQ(items[0], ThirdUUID);

		// Removal still never creates structure.
		plist::dictionary_t bare;
		OAK_ASSERT(!bundles::remove_uuid_from_main_menu(bare, BundleUUID, BundleUUID, ThirdUUID));
		OAK_ASSERT(bare.empty());

		// A rejected insert validates before materialising: no mainMenu
		// structure is left behind on a bundle that had none.
		plist::dictionary_t rejected;
		OAK_ASSERT(!bundles::insert_uuid_into_main_menu(rejected, BundleUUID, BundleUUID, "not-a-uuid"));
		OAK_ASSERT(rejected.empty());
	}
}

void test_move_uuid_within_main_menu ()
{
	// Index insertion clamps and repositions existing entries.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, BundleUUID, ThirdUUID, 0));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 3);
		OAK_ASSERT_EQ(items[0], ThirdUUID);

		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, BundleUUID, FirstUUID, 99));
		items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 3);
		OAK_ASSERT_EQ(items[0], ThirdUUID);
		OAK_ASSERT_EQ(items[1], SecondUUID);
		OAK_ASSERT_EQ(items[2], FirstUUID);

		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, MenuUUID, ThirdUUID, 0));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.submenus." + MenuUUID + ".items")[0], ThirdUUID);
		OAK_ASSERT(!bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, ThirdUUID, SecondUUID, 0));
	}

	// Index insertion materializes a missing top-level menu as well.
	{
		plist::dictionary_t empty;
		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(empty, BundleUUID, BundleUUID, FirstUUID, 0));
		auto items = items_at(empty, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 1);
		OAK_ASSERT_EQ(items[0], FirstUUID);
	}

	// A known submenu entry with no items array (hand-edited plist) is
	// materialized with its name intact; an unknown submenu still fails.
	{
		plist::dictionary_t info = make_info_plist();
		auto mainMenu = plist::get<plist::dictionary_t>(&info["mainMenu"]);
		OAK_ASSERT(mainMenu);
		auto submenus = plist::get<plist::dictionary_t>(&(*mainMenu)["submenus"]);
		OAK_ASSERT(submenus);
		auto submenu = plist::get<plist::dictionary_t>(&(*submenus)[MenuUUID]);
		OAK_ASSERT(submenu);
		submenu->erase("items");

		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, MenuUUID, SecondUUID, 0));
		auto items = items_at(info, "mainMenu.submenus." + MenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 1);
		OAK_ASSERT_EQ(items[0], SecondUUID);
		std::string name;
		OAK_ASSERT(plist::get_key_path(info, "mainMenu.submenus." + MenuUUID + ".name", name));
		OAK_ASSERT_EQ(name, "Extras");
	}

	// Removal composes with insertion into a move across menus.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::remove_uuid_from_main_menu(info, BundleUUID, BundleUUID, SecondUUID));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 1);

		OAK_ASSERT(bundles::remove_uuid_from_main_menu(info, BundleUUID, BundleUUID, SecondUUID));
		OAK_ASSERT(!bundles::remove_uuid_from_main_menu(info, BundleUUID, ThirdUUID, SecondUUID));
		OAK_ASSERT(!bundles::remove_uuid_from_main_menu(info, BundleUUID, BundleUUID, "not-a-uuid"));

		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, MenuUUID, SecondUUID, 0));
		auto items = items_at(info, "mainMenu.submenus." + MenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 2);
		OAK_ASSERT_EQ(items[0], SecondUUID);
		OAK_ASSERT_EQ(items[1], FirstUUID);
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 1);
	}
}

void test_submenu_and_separator_main_menu ()
{
	std::string const NewMenuUUID = "A1B2C3D4-2981-402D-B039-A63949FBDA12";

	// A fresh submenu gets a record with a name and an empty items array …
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::add_submenu_to_main_menu(info, NewMenuUUID, "New Category"));
		auto items = items_at(info, "mainMenu.submenus." + NewMenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 0);

		// … which then addresses like any loaded submenu.
		OAK_ASSERT(bundles::insert_uuid_into_main_menu_at_index(info, BundleUUID, NewMenuUUID, FirstUUID, 0));
		items = items_at(info, "mainMenu.submenus." + NewMenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 1);
		OAK_ASSERT_EQ(items[0], FirstUUID);

		// Re-adding refreshes the name but keeps the items.
		OAK_ASSERT(bundles::add_submenu_to_main_menu(info, NewMenuUUID, "Renamed"));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.submenus." + NewMenuUUID + ".items").size(), 1);

		OAK_ASSERT(!bundles::add_submenu_to_main_menu(info, "not-a-uuid", "Bogus"));
	}

	// Dividers insert (and de-duplicate) as the divider token, clamped.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, BundleUUID, 1));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 3);
		OAK_ASSERT_EQ(items[1], "------------------------------------");

		// Clamped to the end, and — like the block below — never collapsed:
		// the divider already there survives, so this appends a second one.
		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, BundleUUID, 99));
		items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 4);
		OAK_ASSERT_EQ(items[1], items[3]);

		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, MenuUUID, 0));
		items = items_at(info, "mainMenu.submenus." + MenuUUID + ".items");
		OAK_ASSERT_EQ(items.size(), 2);
		OAK_ASSERT_EQ(items[0], "------------------------------------");

		OAK_ASSERT(!bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, "not-a-uuid", 0));
		OAK_ASSERT(!bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, ThirdUUID, 0));
	}

	// Dividers delete by position: a value erase would take out every divider
	// in the menu, since they share one token.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, BundleUUID, 1));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 3);

		OAK_ASSERT(bundles::remove_separator_from_main_menu_at_index(info, BundleUUID, BundleUUID, 1));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 2);
		OAK_ASSERT_EQ(items[0], FirstUUID);
		OAK_ASSERT_EQ(items[1], SecondUUID);

		// A plain item at the slot, a bad index, and a missing menu refuse
		// without touching the plist.
		plist::dictionary_t const original = info;
		OAK_ASSERT(!bundles::remove_separator_from_main_menu_at_index(info, BundleUUID, BundleUUID, 0));
		OAK_ASSERT(!bundles::remove_separator_from_main_menu_at_index(info, BundleUUID, BundleUUID, 99));
		OAK_ASSERT(!bundles::remove_separator_from_main_menu_at_index(info, BundleUUID, MenuUUID, 99));
		OAK_ASSERT(!bundles::remove_separator_from_main_menu_at_index(info, BundleUUID, "not-a-uuid", 0));
		OAK_ASSERT(plist::equal(info, original));
	}

	// Inserting a divider never collapses the dividers already there: they
	// share one token, so an erase-all-first would take them all out.
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, BundleUUID, 1));
		OAK_ASSERT(bundles::insert_separator_into_main_menu_at_index(info, BundleUUID, BundleUUID, 1));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 4);
		OAK_ASSERT_EQ(items[0], FirstUUID);
		OAK_ASSERT_EQ(items[3], SecondUUID);
		OAK_ASSERT_EQ(items[1], items[2]);
	}
}

void test_notification_batch ()
{
	struct counting_callback_t : bundles::callback_t
	{
		int count = 0;
		void bundles_did_change () { ++count; }
	};

	counting_callback_t counter;
	bundles::add_callback(&counter);

	// Throwaway uuids: unknown to the index, so the mutations below only
	// exercise notification flow, never fixture items.
	oak::uuid_t const menu = oak::uuid_t().generate();
	oak::uuid_t const item = oak::uuid_t().generate();

	{
		bundles::notification_batch_t batch;
		bundles::add_to_menu(menu, item);
		bundles::add_to_menu_at_index(menu, item, 0);
		bundles::remove_from_menu(menu, item);
		OAK_ASSERT_EQ(counter.count, 0);

		// Batches nest: the inner exit stays silent …
		{
			bundles::notification_batch_t inner;
			bundles::add_to_menu(menu, item);
			OAK_ASSERT_EQ(counter.count, 0);
		}
		OAK_ASSERT_EQ(counter.count, 0);
	}
	// … and the outermost exit fires exactly once.
	OAK_ASSERT_EQ(counter.count, 1);

	// Unbalanced resume is a no-op, never a phantom notification.
	bundles::resume_notifications();
	OAK_ASSERT_EQ(counter.count, 1);

	bundles::remove_callback(&counter);
	bundles::remove_from_menu(menu, item);
}

void test_callback_destroyed_mid_dispatch_is_skipped ()
{
	// A handler may tear down documents whose destruction unregisters a
	// later callback (grammars live and die with their owners). The
	// in-flight dispatch must skip the stale entry, not call into it.
	struct victim_t : bundles::callback_t
	{
		int* count;
		victim_t (int* count) : count(count) { }
		void bundles_did_change () { ++(*count); }
	};
	struct killer_t : bundles::callback_t
	{
		victim_t* victim = nullptr;
		int count = 0;
		void bundles_did_change ()
		{
			++count;
			bundles::remove_callback(victim);
			delete victim;
			victim = nullptr;
		}
	};

	int victimCount = 0;
	killer_t killer;
	killer.victim = new victim_t(&victimCount);
	bundles::add_callback(&killer);
	bundles::add_callback(killer.victim);

	oak::uuid_t const menu = oak::uuid_t().generate();
	oak::uuid_t const item = oak::uuid_t().generate();
	bundles::add_to_menu(menu, item);

	OAK_ASSERT_EQ(killer.count, 1);
	OAK_ASSERT(!killer.victim);
	OAK_ASSERT_EQ(victimCount, 0);

	bundles::remove_callback(&killer);
	bundles::remove_from_menu(menu, item);
}

void test_remove_separator_from_menu_at_index ()
{
	oak::uuid_t const bundleUUID = oak::uuid_t().generate();
	oak::uuid_t const menuUUID   = oak::uuid_t().generate();
	oak::uuid_t const firstUUID  = oak::uuid_t().generate();
	oak::uuid_t const secondUUID = oak::uuid_t().generate();
	oak::uuid_t const sepUUID    = bundles::item_t::menu_item_separator()->uuid();

	auto bundle = std::make_shared<bundles::item_t>(bundleUUID, bundles::item_ptr(), bundles::kItemTypeBundle);
	auto menu   = std::make_shared<bundles::item_t>(menuUUID, bundle, bundles::kItemTypeMenu);
	auto first  = std::make_shared<bundles::item_t>(firstUUID, bundle, bundles::kItemTypeSnippet);
	auto second = std::make_shared<bundles::item_t>(secondUUID, bundle, bundles::kItemTypeSnippet);
	OAK_ASSERT(bundles::set_index(
		std::vector<bundles::item_ptr>{ bundles::item_t::menu_item_separator(), bundle, menu, first, second },
		std::map<oak::uuid_t, std::vector<oak::uuid_t>>{ { bundleUUID, { menuUUID } }, { menuUUID, { firstUUID, sepUUID, secondUUID } } }
	));

	auto member_uuids = [&]{
		std::vector<oak::uuid_t> res;
		for(auto const& item : menu->menu(true))
			res.push_back(item->uuid());
		return res;
	};
	{
		auto members = member_uuids();
		OAK_ASSERT_EQ(members.size(), 3);
		OAK_ASSERT(members[0] == firstUUID);
		OAK_ASSERT(members[1] == sepUUID);
		OAK_ASSERT(members[2] == secondUUID);
	}

	// A plain item at the slot, a bad index, and a missing menu are no-ops.
	bundles::remove_separator_from_menu_at_index(menuUUID, 0);
	bundles::remove_separator_from_menu_at_index(menuUUID, 99);
	bundles::remove_separator_from_menu_at_index(oak::uuid_t().generate(), 0);
	{
		auto members = member_uuids();
		OAK_ASSERT_EQ(members.size(), 3);
		OAK_ASSERT(members[1] == sepUUID);
	}

	// The divider slot goes; neighbors keep their order.
	bundles::remove_separator_from_menu_at_index(menuUUID, 1);
	{
		auto members = member_uuids();
		OAK_ASSERT_EQ(members.size(), 2);
		OAK_ASSERT(members[0] == firstUUID);
		OAK_ASSERT(members[1] == secondUUID);
	}

	// Divider inserts do not collapse: the ones already there survive.
	bundles::add_to_menu_at_index(menuUUID, sepUUID, 1, false);
	bundles::add_to_menu_at_index(menuUUID, sepUUID, 1, false);
	{
		auto members = member_uuids();
		OAK_ASSERT_EQ(members.size(), 4);
		OAK_ASSERT(members[0] == firstUUID);
		OAK_ASSERT(members[1] == sepUUID);
		OAK_ASSERT(members[2] == sepUUID);
		OAK_ASSERT(members[3] == secondUUID);
	}

	// This test replaces the shared index: rebuild the standard fixtures for
	// whatever runs after it in the suite.
	setup_fixtures();
}

void test_rename_item_updates_name_lookup ()
{
	oak::uuid_t const bundleUUID = oak::uuid_t().generate();
	oak::uuid_t const itemUUID   = oak::uuid_t().generate();

	auto bundle = std::make_shared<bundles::item_t>(bundleUUID, bundles::item_ptr(), bundles::kItemTypeBundle);
	auto item   = std::make_shared<bundles::item_t>(itemUUID, bundle, bundles::kItemTypeSnippet);
	item->set_name("Extras");
	OAK_ASSERT(bundles::set_index(
		std::vector<bundles::item_ptr>{ bundle, item },
		std::map<oak::uuid_t, std::vector<oak::uuid_t>>{ { bundleUUID, { itemUUID } } }
	));

	// Snippets are covered by the default query kind; menus are not, so a
	// menu would never surface through this lookup.
	auto hits = bundles::query(bundles::kFieldName, "Extras");
	OAK_ASSERT_EQ(hits.size(), 1);

	bundles::rename_item(itemUUID, "Renamed");
	OAK_ASSERT(bundles::query(bundles::kFieldName, "Extras").empty());
	auto renamed = bundles::query(bundles::kFieldName, "Renamed");
	OAK_ASSERT_EQ(renamed.size(), 1);
	OAK_ASSERT(renamed[0]->uuid() == itemUUID);

	// This test replaces the shared index: rebuild the standard fixtures for
	// whatever runs after it in the suite.
	setup_fixtures();
}

void test_menu_members ()
{
	oak::uuid_t const bundleUUID = oak::uuid_t().generate();
	oak::uuid_t const menuUUID   = oak::uuid_t().generate();
	oak::uuid_t const firstUUID  = oak::uuid_t().generate();
	oak::uuid_t const secondUUID = oak::uuid_t().generate();

	auto bundle = std::make_shared<bundles::item_t>(bundleUUID, bundles::item_ptr(), bundles::kItemTypeBundle);
	auto menu   = std::make_shared<bundles::item_t>(menuUUID, bundle, bundles::kItemTypeMenu);
	auto first  = std::make_shared<bundles::item_t>(firstUUID, bundle, bundles::kItemTypeSnippet);
	auto second = std::make_shared<bundles::item_t>(secondUUID, bundle, bundles::kItemTypeSnippet);
	OAK_ASSERT(bundles::set_index(
		std::vector<bundles::item_ptr>{ bundle, menu, first, second },
		std::map<oak::uuid_t, std::vector<oak::uuid_t>>{ { bundleUUID, { menuUUID } }, { menuUUID, { firstUUID, secondUUID } } }
	));

	auto members = bundles::menu_members(menuUUID);
	OAK_ASSERT_EQ(members.size(), 2);
	OAK_ASSERT(members[0] == firstUUID);
	OAK_ASSERT(members[1] == secondUUID);
	OAK_ASSERT(bundles::menu_members(oak::uuid_t()).empty());

	// This test replaces the shared index: rebuild the standard fixtures for
	// whatever runs after it in the suite.
	setup_fixtures();
}

void test_remove_submenu_from_main_menu ()
{
	// Removal takes out the parent reference and the submenu record …
	{
		plist::dictionary_t info = make_info_plist();
		OAK_ASSERT(bundles::insert_uuid_into_main_menu(info, BundleUUID, BundleUUID, MenuUUID));
		OAK_ASSERT_EQ(items_at(info, "mainMenu.items").size(), 3);

		OAK_ASSERT(bundles::remove_submenu_from_main_menu(info, BundleUUID, BundleUUID, MenuUUID));
		auto items = items_at(info, "mainMenu.items");
		OAK_ASSERT_EQ(items.size(), 2);
		OAK_ASSERT_EQ(items[0], FirstUUID);
		OAK_ASSERT_EQ(items[1], SecondUUID);

		std::string name;
		OAK_ASSERT(!plist::get_key_path(info, "mainMenu.submenus." + MenuUUID + ".name", name));
	}

	// … and fails without touching the plist for unknown submenus, unknown
	// parents, or malformed input.
	{
		plist::dictionary_t info = make_info_plist();
		plist::dictionary_t const original = info;
		OAK_ASSERT(!bundles::remove_submenu_from_main_menu(info, BundleUUID, BundleUUID, ThirdUUID));
		OAK_ASSERT(!bundles::remove_submenu_from_main_menu(info, BundleUUID, ThirdUUID, MenuUUID));
		OAK_ASSERT(!bundles::remove_submenu_from_main_menu(info, BundleUUID, BundleUUID, "not-a-uuid"));
		OAK_ASSERT(plist::equal(info, original));
	}
}

void test_menu_index_for_pane_slot ()
{
	oak::uuid_t const bundleUUID = oak::uuid_t().generate();
	oak::uuid_t const firstUUID  = oak::uuid_t().generate();
	oak::uuid_t const secondUUID = oak::uuid_t().generate();
	oak::uuid_t const orphanUUID = oak::uuid_t().generate();

	auto bundle = std::make_shared<bundles::item_t>(bundleUUID, bundles::item_ptr(), bundles::kItemTypeBundle);
	auto first  = std::make_shared<bundles::item_t>(firstUUID, bundle, bundles::kItemTypeSnippet);
	auto second = std::make_shared<bundles::item_t>(secondUUID, bundle, bundles::kItemTypeSnippet);
	// The membership list mirrors a loaded menu: the orphan uuid is kept
	// (the loader only drops invalid strings), the divider token arrives
	// as the shared separator uuid.
	OAK_ASSERT(bundles::set_index(
		std::vector<bundles::item_ptr>{ bundle, first, second },
		std::map<oak::uuid_t, std::vector<oak::uuid_t>>{ { bundleUUID, { firstUUID, orphanUUID, bundles::kSeparatorUUID, secondUUID } } }
	));

	// Visible rows are first | divider | second: the orphan uuid and the
	// invalid string draw nothing but keep their slots. The pair is {plist
	// index, membership index}: the invalid string never reaches the latter.
	std::string const orphan = to_s(orphanUUID);
	std::vector<std::string> const entries{ to_s(firstUUID), orphan, kSeparatorString, "", to_s(secondUUID) };
	auto at = [&](size_t slot, std::set<std::string> const& dragged = std::set<std::string>()){
		return bundles::menu_indexes_for_pane_slot(entries, slot, dragged);
	};
	OAK_ASSERT(at(0) == std::make_pair(0ul, 0ul));
	OAK_ASSERT(at(1) == std::make_pair(2ul, 2ul));
	OAK_ASSERT(at(2) == std::make_pair(4ul, 3ul));
	OAK_ASSERT(at(3) == std::make_pair(5ul, 4ul));
	OAK_ASSERT(at(9) == std::make_pair(5ul, 4ul));
	OAK_ASSERT(at(0, { to_s(firstUUID) }) == std::make_pair(1ul, 1ul));
	OAK_ASSERT(at(1, { to_s(firstUUID) }) == std::make_pair(3ul, 2ul));

	// This test replaces the shared index: rebuild the standard fixtures for
	// whatever runs after it in the suite.
	setup_fixtures();
}
