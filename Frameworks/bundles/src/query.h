#ifndef BUNDLES_QUERY_H_7L9NPR0I
#define BUNDLES_QUERY_H_7L9NPR0I

#include "item.h"
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace bundles
{
	bool set_index (std::vector<item_ptr> const& items, std::map< oak::uuid_t, std::vector<oak::uuid_t> > const& menus);
	inline bool set_index (std::vector<item_ptr> const& items) { return set_index(items, std::map< oak::uuid_t, std::vector<oak::uuid_t> >()); }

	struct callback_t
	{
		virtual ~callback_t () { }
		virtual void bundles_will_change () { }
		virtual void bundles_did_change ()  { }
	};

	void add_callback (callback_t* cb);
	void remove_callback (callback_t* cb);
	void add_item (item_ptr item);
	void remove_item (item_ptr item);

	// Coalesce change notifications: while suspended, bundles_did_change is
	// swallowed and a single notification fires when the outermost
	// resume_notifications() runs. Lets multi-step mutations (a drag move,
	// a submenu insert) present one consistent state instead of N
	// half-mutated ones. suspend/resume nest; resume without suspend is a
	// no-op.
	void suspend_notifications ();
	void resume_notifications ();

	struct notification_batch_t
	{
		notification_batch_t ()  { suspend_notifications(); }
		~notification_batch_t () { resume_notifications(); }
	};

	// Record item_uuid as a member of the menu identified by menu_uuid
	// (the bundle uuid addresses the top-level menu), placed directly after
	// after_uuid, or appended when after_uuid is nil or absent. The entry is
	// de-duplicated and the item’s parent menu is updated. This mutates the
	// in-memory index only; callers persist the change separately, e.g. via
	// insert_uuid_into_main_menu() on the bundle’s info.plist dictionary.
	void add_to_menu (oak::uuid_t const& menu_uuid, oak::uuid_t const& item_uuid, oak::uuid_t const& after_uuid = oak::uuid_t());

	// Insert item_uuid at index in the menu (clamped to the end),
	// de-duplicated unless dedup is false, updating the item’s parent menu.
	// Pass false for dividers: they share one uuid, so de-duplicating would
	// delete every divider already in the menu. In-memory index only.
	void add_to_menu_at_index (oak::uuid_t const& menu_uuid, oak::uuid_t const& item_uuid, size_t index, bool dedup = true);

	// Remove item_uuid from the menu, resetting the item’s parent menu to its
	// bundle. In-memory index only; persist with remove_uuid_from_main_menu().
	// Unknown menus or entries are a no-op.
	void remove_from_menu (oak::uuid_t const& menu_uuid, oak::uuid_t const& item_uuid);
	// Remove the divider at index in the menu. Positional, like its plist
	// counterpart: dividers share one uuid, so a value-based erase would take
	// out every divider in the menu. A wrong slot (or missing menu) is a no-op.
	// In-memory index only; persist with
	// remove_separator_from_main_menu_at_index().
	void remove_separator_from_menu_at_index (oak::uuid_t const& menu_uuid, size_t index);

// Member uuids of the menu, in order; unknown menus give an empty list.
// Raw index state: remove_item() does not scrub memberships, so trashed
// items leave ghosts — callers judging emptiness should resolve each member
// via lookup(), mirroring how the loader skips unresolvable entries.
	std::vector<oak::uuid_t> menu_members (oak::uuid_t const& menu_uuid);

// Translate a visible pane slot into {plist index, membership index} for
// the menu’s items array. Panes skip entries they cannot draw — unknown,
// deleted, or hidden uuids — so a raw row number lands high whenever such
// entries sit above the slot; walking the array and counting only drawable,
// non-dragged entries keeps drops and inserts where pointed. Skipped
// entries keep their positions: visible moves never shuffle them. Slots
// past the last drawable row append. Coordinates are post-removal: pass
// the uuids moving away in dragged.
	std::pair<size_t, size_t> menu_indexes_for_pane_slot (std::vector<std::string> const& entries, size_t slot, std::set<std::string> const& dragged);

// Change the item’s name, invalidating name lookups. In-memory index only;
// persist submenu renames with add_submenu_to_main_menu().
	void rename_item (oak::uuid_t const& item_uuid, std::string const& new_name);

	std::vector<item_ptr> query (std::string const& field, std::string const& value, scope::context_t const& scope = scope::wildcard, int kind = kItemTypeMost, oak::uuid_t const& bundle = oak::uuid_t(), bool filter = true, bool includeDisabledItems = false, bool resolveProxyItems = true);
	std::vector<item_ptr> items_for_proxy (item_ptr proxyItem, scope::context_t const& scope = scope::wildcard, int kind = kItemTypeCommand|kItemTypeDragCommand|kItemTypeGrammar|kItemTypeMacro|kItemTypeSnippet|kItemTypeProxy|kItemTypeTheme, oak::uuid_t const& bundle = oak::uuid_t(), bool filter = true, bool includeDisabledItems = false);
	item_ptr lookup (oak::uuid_t const& uuid);
	std::string name_with_selection (item_ptr const& item, bool hasSelection);
	std::string menu_path (item_ptr item);
	std::string key_equivalent (item_ptr const& item);

} /* bundles */

#endif /* end of include guard: BUNDLES_QUERY_H_7L9NPR0I */
