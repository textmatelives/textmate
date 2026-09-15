#ifndef LOAD_H_C8BVI372
#define LOAD_H_C8BVI372

#include "item.h"
#include <plist/fs_cache.h>

std::pair<std::vector<bundles::item_ptr>, std::map< oak::uuid_t, std::vector<oak::uuid_t>>> create_bundle_index (std::vector<std::string> const& bundlesPaths, plist::cache_t& cache);

// Divider token stored in mainMenu items arrays (as opposed to a uuid).
extern std::string const kSeparatorString;

namespace bundles
{
// Insert item_uuid into the “items” array of the menu addressed by menu_uuid
// inside info_plist’s mainMenu (bundle_uuid addresses the top-level items;
// any other uuid addresses mainMenu.submenus.<uuid>.items), placed directly
// after after_uuid, or appended when after_uuid is empty or absent. The entry
// is de-duplicated. Returns false without touching info_plist when either
// uuid is invalid or the addressed menu does not exist.
bool insert_uuid_into_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid, std::string const& after_uuid = std::string());

// Insert item_uuid at index in the addressed menu’s items array (clamped to
// the end), de-duplicated. Same addressing and failure contract as above.
bool insert_uuid_into_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid, size_t index);

// Remove item_uuid from the addressed menu’s items array. Returns false
// without touching info_plist when the menu does not exist; removing an
// absent entry still returns true.
bool remove_uuid_from_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid);

// Insert a divider into the addressed menu’s items array at index (clamped
// to the end). Same addressing as above, except separators are stored as
// the divider token rather than a uuid — and unlike the uuid insert this
// never de-duplicates, since dividers share one token and erasing it would
// take out every divider in the menu. Returns false without touching
// info_plist when either uuid is invalid or the menu is missing.
bool insert_separator_into_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, size_t index);

// Create mainMenu.submenus.<submenu_uuid> = { name, items:() } so a fresh
// submenu has a record to own its items. Existing records keep their items
// and have their name refreshed. Returns false without touching info_plist
// when submenu_uuid is invalid.
bool add_submenu_to_main_menu (plist::dictionary_t& info_plist, std::string const& submenu_uuid, std::string const& name);

// Remove the divider token at index in the addressed menu’s items array.
// Unlike the uuid removers this is positional (dividers share one token, so
// a value-based erase would take out every divider in the menu). Returns
// false without touching info_plist when the menu is missing, the index is
// out of bounds, or the entry there is not a divider.
bool remove_separator_from_main_menu_at_index (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, size_t index);

// Delete mainMenu.submenus.<submenu_uuid> and remove its reference from the
// addressed parent menu’s items array. Returns false without touching
// info_plist when the parent menu or the submenu record does not exist.
bool remove_submenu_from_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& parent_menu_uuid, std::string const& submenu_uuid);
}

#endif /* end of include guard: LOAD_H_C8BVI372 */
