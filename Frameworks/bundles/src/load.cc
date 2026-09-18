#include "load.h"
#include <plist/delta.h>
#include <regexp/glob.h>
#include <text/format.h>
#include <oak/debug.h>

std::string const kSeparatorString = "------------------------------------";

static std::vector<oak::uuid_t> to_menu (plist::array_t const& uuids, std::string const& path)
{
	std::vector<oak::uuid_t> res;
	for(auto uuid : uuids)
	{
		std::string const* str = plist::get<std::string>(&uuid);
		if(str && oak::uuid_t::is_valid(*str))
				res.push_back(*str == kSeparatorString ? bundles::kSeparatorUUID : oak::uuid_t(*str));
		else	os_log_error(OS_LOG_DEFAULT, "Invalid uuid (%{public}s) in ‘%{public}s’", to_s(uuid).c_str(), path.c_str());
	}
	return res;
}

static plist::array_t* main_menu_items (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, bool createTopLevel)
{
	auto main_menu_it = info_plist.find("mainMenu");
	plist::dictionary_t* main_menu = main_menu_it != info_plist.end() ? plist::get<plist::dictionary_t>(&main_menu_it->second) : nullptr;
	if(!main_menu)
	{
		// Bundles that never had an explicit order (fresh leftovers) have no
		// mainMenu at all: materialize it so a validated drop can persist.
		// Removal stays best-effort and never creates structure.
		if(!createTopLevel)
			return nullptr;
		main_menu_it = info_plist.emplace("mainMenu", plist::dictionary_t()).first;
		main_menu = plist::get<plist::dictionary_t>(&main_menu_it->second);
		if(!main_menu)
			return nullptr;
	}

	if(menu_uuid == bundle_uuid)
	{
		auto items_it = main_menu->find("items");
		if(items_it == main_menu->end())
		{
			if(!createTopLevel)
				return nullptr;
			items_it = main_menu->emplace("items", plist::array_t()).first;
		}
		return plist::get<plist::array_t>(&items_it->second);
	}

	if(auto sub_menus_it = main_menu->find("submenus"); sub_menus_it != main_menu->end())
	{
		if(plist::dictionary_t* sub_menus = plist::get<plist::dictionary_t>(&sub_menus_it->second))
		{
			if(auto sub_menu_it = sub_menus->find(menu_uuid); sub_menu_it != sub_menus->end())
			{
				if(plist::dictionary_t* sub_menu = plist::get<plist::dictionary_t>(&sub_menu_it->second))
				{
					auto items_it = sub_menu->find("items");
					if(items_it == sub_menu->end())
					{
						// A known submenu entry with no items array yet
						// (hand-edited plist): materialize the array, keeping
						// the entry’s name. A missing entry stays a failure —
						// the loader drops nameless submenu records, so
						// inventing one here would lose the menu on reload.
						if(!createTopLevel)
							return nullptr;
						items_it = sub_menu->emplace("items", plist::array_t()).first;
					}
					return plist::get<plist::array_t>(&items_it->second);
				}
			}
		}
	}
	return nullptr;
}

static void erase_uuid_from_array (plist::array_t& items, std::string const& item_uuid)
{
	items.erase(std::remove_if(items.begin(), items.end(), [&](plist::any_t const& entry){
		std::string const* str = plist::get<std::string>(&entry);
		return str && *str == item_uuid;
	}), items.end());
}

bool bundles::insert_uuid_into_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid, size_t index)
{
	if(!oak::uuid_t::is_valid(menu_uuid) || !oak::uuid_t::is_valid(item_uuid))
		return false;

	plist::array_t* items = main_menu_items(info_plist, bundle_uuid, menu_uuid, true);
	if(!items)
		return false;

	erase_uuid_from_array(*items, item_uuid);
	items->insert(items->begin() + std::min(index, items->size()), plist::any_t(item_uuid));
	return true;
}

bool bundles::insert_uuid_into_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid, std::string const& after_uuid)
{
	if(!oak::uuid_t::is_valid(menu_uuid) || !oak::uuid_t::is_valid(item_uuid))
		return false;

	plist::array_t* items = main_menu_items(info_plist, bundle_uuid, menu_uuid, true);
	if(!items)
		return false;

	size_t index = items->size();
	if(!after_uuid.empty())
	{
		for(size_t i = 0; i < items->size(); ++i)
		{
			if(std::string const* str = plist::get<std::string>(&(*items)[i]))
			{
				if(*str == after_uuid)
				{
					index = i + 1;
					break;
				}
			}
		}
	}
	return insert_uuid_into_main_menu_at_index(info_plist, bundle_uuid, menu_uuid, item_uuid, index);
}

bool bundles::remove_uuid_from_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid)
{
	if(!oak::uuid_t::is_valid(menu_uuid) || !oak::uuid_t::is_valid(item_uuid))
		return false;

	plist::array_t* items = main_menu_items(info_plist, bundle_uuid, menu_uuid, false);
	if(!items)
		return false;

	erase_uuid_from_array(*items, item_uuid);
	return true;
}

bool bundles::insert_separator_into_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, size_t index)
{
	if(!oak::uuid_t::is_valid(menu_uuid))
		return false;

	plist::array_t* items = main_menu_items(info_plist, bundle_uuid, menu_uuid, true);
	if(!items)
		return false;

	// No erase-all first: dividers share one token, so de-duplicating here
	// would delete every divider already in the menu.
	items->insert(items->begin() + std::min(index, items->size()), plist::any_t(kSeparatorString));
	return true;
}

bool bundles::remove_separator_from_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, size_t index)
{
	if(!oak::uuid_t::is_valid(menu_uuid))
		return false;

	plist::array_t* items = main_menu_items(info_plist, bundle_uuid, menu_uuid, false);
	if(!items || index >= items->size())
		return false;

	std::string const* str = plist::get<std::string>(&(*items)[index]);
	if(!str || *str != kSeparatorString)
		return false;

	items->erase(items->begin() + index);
	return true;
}

bool bundles::remove_submenu_from_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& parent_menu_uuid, std::string const& submenu_uuid)
{
	if(!oak::uuid_t::is_valid(parent_menu_uuid) || !oak::uuid_t::is_valid(submenu_uuid))
		return false;

	// The record must exist: the loader drops nameless submenu records, so
	// deleting a bare parent reference would lose nothing but also fix
	// nothing — refuse instead. Removal never creates structure.
	auto main_menu_it = info_plist.find("mainMenu");
	plist::dictionary_t* main_menu = main_menu_it != info_plist.end() ? plist::get<plist::dictionary_t>(&main_menu_it->second) : nullptr;
	if(!main_menu)
		return false;
	auto sub_menus_it = main_menu->find("submenus");
	plist::dictionary_t* sub_menus = sub_menus_it != main_menu->end() ? plist::get<plist::dictionary_t>(&sub_menus_it->second) : nullptr;
	if(!sub_menus || sub_menus->find(submenu_uuid) == sub_menus->end())
		return false;

	// Parent reference first: it fails cleanly (untouched) when the parent
	// menu is missing, before the record goes away.
	if(!remove_uuid_from_main_menu(info_plist, bundle_uuid, parent_menu_uuid, submenu_uuid))
		return false;
	sub_menus->erase(submenu_uuid);
	return true;
}

bool bundles::add_submenu_to_main_menu (plist::dictionary_t& info_plist, std::string const& submenu_uuid, std::string const& name)
{
	if(!oak::uuid_t::is_valid(submenu_uuid))
		return false;

	auto main_menu_it = info_plist.find("mainMenu");
	plist::dictionary_t* main_menu = main_menu_it != info_plist.end() ? plist::get<plist::dictionary_t>(&main_menu_it->second) : nullptr;
	if(!main_menu)
	{
		main_menu_it = info_plist.emplace("mainMenu", plist::dictionary_t()).first;
		main_menu = plist::get<plist::dictionary_t>(&main_menu_it->second);
		if(!main_menu)
			return false;
	}

	auto sub_menus_it = main_menu->find("submenus");
	plist::dictionary_t* sub_menus = sub_menus_it != main_menu->end() ? plist::get<plist::dictionary_t>(&sub_menus_it->second) : nullptr;
	if(!sub_menus)
	{
		sub_menus_it = main_menu->emplace("submenus", plist::dictionary_t()).first;
		sub_menus = plist::get<plist::dictionary_t>(&sub_menus_it->second);
		if(!sub_menus)
			return false;
	}

	auto sub_menu_it = sub_menus->find(submenu_uuid);
	plist::dictionary_t* sub_menu = sub_menu_it != sub_menus->end() ? plist::get<plist::dictionary_t>(&sub_menu_it->second) : nullptr;
	if(!sub_menu)
	{
		sub_menu_it = sub_menus->emplace(submenu_uuid, plist::dictionary_t()).first;
		sub_menu = plist::get<plist::dictionary_t>(&sub_menu_it->second);
		if(!sub_menu)
			return false;
		sub_menu->emplace("items", plist::array_t());
	}

	(*sub_menu)["name"] = name;
	if(sub_menu->find("items") == sub_menu->end())
		sub_menu->emplace("items", plist::array_t());
	return true;
}

static void remove_cycles (oak::uuid_t const& menuUUID, std::map< oak::uuid_t, std::vector<oak::uuid_t> >& menus, std::set<oak::uuid_t> parents = { })
{
	auto pair = menus.find(menuUUID);
	if(pair != menus.end())
	{
		parents.insert(menuUUID);
		pair->second.erase(std::remove_if(pair->second.begin(), pair->second.end(), [&parents](oak::uuid_t const& uuid) { return parents.find(uuid) != parents.end(); }), pair->second.end());
		for(auto const& uuid : pair->second)
			remove_cycles(uuid, menus, parents);
	}
}

std::pair<std::vector<bundles::item_ptr>, std::map< oak::uuid_t, std::vector<oak::uuid_t>>> create_bundle_index (std::vector<std::string> const& bundlesPaths, plist::cache_t& cache)
{
	struct delta_item_t
	{
		delta_item_t (bundles::item_ptr item, plist::dictionary_t const& plist) : item(item), plist(plist) { }

		bundles::item_ptr item;
		plist::dictionary_t plist;
	};

	std::vector<bundles::item_ptr> items(1, bundles::item_t::menu_item_separator());
	std::map< oak::uuid_t, std::vector<oak::uuid_t> > menus;

	std::map<oak::uuid_t, delta_item_t> deltaItems;
	std::set<oak::uuid_t> loadedItems;

	bool local = true;
	for(auto const& bundlesPath : bundlesPaths)
	{
		for(auto const& bundlePath : cache.entries(bundlesPath, "*.tm[Bb]undle"))
		{
			bundles::item_ptr bundle;
			std::set<oak::uuid_t> hiddenItems;
			bool skipEclipsedBundle = false;

			auto const entries = cache.entries(bundlePath, "{[Ii]nfo.plist,Commands,DragCommands,Macros,Preferences,Proxies,Snippets,Syntaxes,Themes}");
			for(auto const& infoPlistPath : entries)
			{
				std::string const name = path::name(infoPlistPath);
				if(name != "info.plist" && name != "Info.plist")
					continue;

				oak::uuid_t bundleUUID;
				plist::dictionary_t plist = cache.content(infoPlistPath);
				if(!plist::get_key_path(plist, bundles::kFieldUUID, bundleUUID))
				{
					std::string uuidStr;
					if(plist::get_key_path(plist, bundles::kFieldUUID, uuidStr))
							os_log_error(OS_LOG_DEFAULT, "Skip ‘%{public}s’, invalid UUID ‘%{public}s’", infoPlistPath.c_str(), uuidStr.c_str());
					else	os_log_error(OS_LOG_DEFAULT, "Skip ‘%{public}s’, no UUID", infoPlistPath.c_str());
					break;
				}

				bundle = std::make_shared<bundles::item_t>(bundleUUID, bundles::item_ptr(), bundles::kItemTypeBundle, local);
				bundle->add_path(infoPlistPath);

				bool isDelta = false;
				if(plist::get_key_path(plist, bundles::kFieldIsDelta, isDelta) && isDelta)
				{
					deltaItems.emplace(bundleUUID, delta_item_t(bundle, plist));
					break;
				}

				std::map<oak::uuid_t, delta_item_t>::iterator deltaItem = deltaItems.find(bundleUUID);
				if(deltaItem != deltaItems.end())
				{
					bundle = deltaItem->second.item;
					bundle->add_path(infoPlistPath);

					std::vector<plist::dictionary_t> plists;
					plists.push_back(deltaItem->second.plist);
					plists.push_back(plist);
					plist = plist::merge_delta(plists);
					deltaItems.erase(deltaItem);
				}
				else if(loadedItems.find(bundleUUID) != loadedItems.end())
				{
					bundle.reset();
					skipEclipsedBundle = true;
					break;
				}

				bundle->initialize(plist);
				items.push_back(bundle);

				// ====================
				// = Load Bundle Menu =
				// ====================

				plist::array_t mainMenu;
				plist::get_key_path(plist, "mainMenu.items", mainMenu);
				menus.emplace(bundleUUID, to_menu(mainMenu, infoPlistPath));

				plist::dictionary_t subMenus;
				plist::get_key_path(plist, "mainMenu.submenus", subMenus);
				for(auto const& submenuIter : subMenus)
				{
					std::string name;
					plist::array_t uuids;
					if(oak::uuid_t::is_valid(submenuIter.first) && plist::get_key_path(submenuIter.second, bundles::kFieldName, name) && plist::get_key_path(submenuIter.second, "items", uuids))
					{
						auto item = std::make_shared<bundles::item_t>(submenuIter.first, bundle, bundles::kItemTypeMenu);
						item->set_name(name);
						items.push_back(item);
						menus.emplace(submenuIter.first, to_menu(uuids, infoPlistPath));
					}
					else
					{
						os_log_error(OS_LOG_DEFAULT, "Invalid uuid (\"%{public}s\") in ‘%{public}s’", submenuIter.first.c_str(), infoPlistPath.c_str());
					}
				}

				remove_cycles(bundleUUID, menus);

				plist::array_t uuids;
				plist::get_key_path(plist, "mainMenu.excludedItems", uuids);
				for(auto const& uuid : uuids)
				{
					std::string const* str = plist::get<std::string>(&uuid);
					if(str && oak::uuid_t::is_valid(*str))
						hiddenItems.insert(*str);
				}

				break;
			}

			if(!bundle)
			{
				if(!skipEclipsedBundle)
					os_log_error(OS_LOG_DEFAULT, "Not a bundle at ‘%{public}s’", bundlePath.c_str());
				continue;
			}

			for(auto dirPath : entries)
			{
				static struct { std::string name; std::string glob; bundles::kind_t kind; } const dirs[] =
				{
					{ "Commands",     "*.{plist,tmDelta,tmCommand}",     bundles::kItemTypeCommand     },
					{ "DragCommands", "*.{plist,tmDelta,tmDragCommand}", bundles::kItemTypeDragCommand },
					{ "Macros",       "*.{plist,tmDelta,tmMacro}",       bundles::kItemTypeMacro       },
					{ "Preferences",  "*.{plist,tmDelta,tmPreferences}", bundles::kItemTypeSettings    },
					{ "Snippets",     "*.{plist,tmDelta,tmSnippet}",     bundles::kItemTypeSnippet     },
					{ "Syntaxes",     "*.{plist,tmDelta,tmLanguage}",    bundles::kItemTypeGrammar     },
					{ "Proxies",      "*.{plist,tmDelta,tmProxy}",       bundles::kItemTypeProxy       },
					{ "Themes",       "*.{plist,tmDelta,tmTheme}",       bundles::kItemTypeTheme       },
				};

				for(auto const& dirInfo : dirs)
				{
					if(path::name(dirPath) != dirInfo.name)
						continue;

					for(auto itemPath : cache.entries(dirPath, dirInfo.glob))
					{
						oak::uuid_t uuid;
						plist::dictionary_t plist = cache.content(itemPath);
						if(!plist::get_key_path(plist, bundles::kFieldUUID, uuid))
						{
							std::string uuidStr;
							if(plist::get_key_path(plist, bundles::kFieldUUID, uuidStr))
									os_log_error(OS_LOG_DEFAULT, "Skip ‘%{public}s’, invalid UUID ‘%{public}s’", itemPath.c_str(), uuidStr.c_str());
							else	os_log_error(OS_LOG_DEFAULT, "Skip ‘%{public}s’, no UUID", itemPath.c_str());
							continue;
						}

						if(loadedItems.find(uuid) != loadedItems.end())
						{
							os_log_error(OS_LOG_DEFAULT, "Skip ‘%{public}s’, item with same UUID loaded from ‘%{public}s’", itemPath.c_str(), text::join((*std::find_if(items.begin(), items.end(), [&uuid](bundles::item_ptr const& item){ return item->uuid() == uuid; }))->paths(), "’, ‘").c_str());
							continue;
						}

						// Don’t load the “TextMate → Update Notification” item (bound to ⌘Q)
						if(uuid == "615998FE-A13B-4199-A670-E5A892A1C43A")
							continue;

						auto item = std::make_shared<bundles::item_t>(uuid, bundle, dirInfo.kind, local);
						item->add_path(itemPath);

						bool isDelta = false;
						if(plist::get_key_path(plist, bundles::kFieldIsDelta, isDelta) && isDelta)
						{
							deltaItems.emplace(uuid, delta_item_t(item, plist));
							continue;
						}

						std::map<oak::uuid_t, delta_item_t>::iterator deltaItem = deltaItems.find(uuid);
						if(deltaItem != deltaItems.end())
						{
							item = deltaItem->second.item;
							item->add_path(itemPath);

							std::vector<plist::dictionary_t> plists;
							plists.push_back(deltaItem->second.plist);
							plists.push_back(plist);
							plist = plist::merge_delta(plists);
							deltaItems.erase(deltaItem);
						}

						if(hiddenItems.find(item->uuid()) != hiddenItems.end())
							plist.emplace(bundles::kFieldHideFromUser, true);

						item->initialize(plist);
						items.push_back(item);

						loadedItems.insert(uuid);
					}

					break;
				}
			}

			if(deltaItems.find(bundle->uuid()) == deltaItems.end())
				loadedItems.insert(bundle->uuid());
		}

		local = false;
	}

	for(ssize_t i = items.size(); i-- > 0; )
	{
		bundles::item_ptr item = items[i];
		if(deltaItems.find(item->bundle_uuid()) != deltaItems.end())
		{
			os_log_error(OS_LOG_DEFAULT, "Orphaned delta (‘%{public}s’) at: %{public}s", item->name().c_str(), text::join(item->paths(), ", ").c_str());
			items.erase(items.begin() + i);
		}
	}

	return { items, menus };
}
