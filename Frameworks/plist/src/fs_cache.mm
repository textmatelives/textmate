#include "fs_cache.h"
#include <io/entries.h>
#include <text/format.h>
#include <oak/debug.h>
#import <Foundation/Foundation.h>

static std::string read_link (std::string const& path)
{
	char buf[PATH_MAX];
	ssize_t len = readlink(path.c_str(), buf, sizeof(buf));
	if(0 < len && len < PATH_MAX)
	{
		return std::string(buf, buf + len);
	}
	else
	{
		std::string errStr = len == -1 ? strerror(errno) : text::format("Result outside allowed range %zd", len);
		os_log_error(OS_LOG_DEFAULT, "readlink(\"%{public}s\"): %{public}s", path.c_str(), errStr.c_str());
	}
	return NULL_STR;
}

namespace plist
{
	// Cache file format version. Bumped from the legacy capnp format (which
	// used 2) to a high sentinel that will never collide with capnp's version
	// field. The new format is an NSKeyedArchiver-encoded NSDictionary whose
	// top-level keys are file paths plus a "__version" key.
	int32_t const cache_t::kPropertyCacheFormatVersion = 100;

	// NSDictionary keys used in the on-disk archive. Kept short to minimize
	// archive size; they are private to this file and never user-visible.
	static NSString* const kArchiveVersionKey = @"__version";
	static NSString* const kArchiveEntriesKey = @"__entries";

	static NSString* const kEntryTypeKey      = @"type";
	static NSString* const kEntryLinkKey      = @"link";
	static NSString* const kEntryGlobKey      = @"glob";
	static NSString* const kEntryModifiedKey  = @"modified";
	static NSString* const kEntryEventIdKey   = @"eventId";
	static NSString* const kEntryContentKey   = @"content"; // NSData (binary plist of the dictionary)
	static NSString* const kEntryEntriesKey   = @"entries"; // NSArray<NSString*>

	// Enum values for the "type" key. Hardcoded to specific integers so the
	// on-disk format does not depend on the order of entry_type_t.
	enum {
		kArchiveEntryTypeFile      = 1,
		kArchiveEntryTypeDirectory = 2,
		kArchiveEntryTypeLink      = 3,
		kArchiveEntryTypeMissing   = 4,
	};

	void cache_t::load (std::string const& path)
	{
		NSData* data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path.c_str()]];
		if(!data)
			return;

		// Allowed classes for the archive root. The archive is a dictionary of
		// dictionaries containing strings, numbers, arrays, and data — all
		// NSSecureCoding-compliant Foundation types.
		NSSet* classes = [NSSet setWithObjects:NSDictionary.class, NSString.class, NSNumber.class, NSArray.class, NSData.class, nil];

		NSError* error = nil;
		id root = nil;
		if(@available(macOS 10.13, *))
			root = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];
		if(!root || ![root isKindOfClass:NSDictionary.class])
			return; // Unreadable / wrong format / leftover capnp file — silently rebuild.

		NSDictionary* archive = (NSDictionary*)root;
		NSNumber* version = archive[kArchiveVersionKey];
		if(![version isKindOfClass:NSNumber.class] || [version intValue] != kPropertyCacheFormatVersion)
		{
			os_log_info(OS_LOG_DEFAULT, "Skip ‘%{public}s’ (version mismatch or stale format)", path.c_str());
			return;
		}

		NSDictionary* entries = archive[kArchiveEntriesKey];
		if(![entries isKindOfClass:NSDictionary.class])
			return;

		for(NSString* key in entries)
		{
			if(![key isKindOfClass:NSString.class])
				continue;
			NSDictionary* node = entries[key];
			if(![node isKindOfClass:NSDictionary.class])
				continue;

			NSNumber* typeNum = node[kEntryTypeKey];
			if(![typeNum isKindOfClass:NSNumber.class])
				continue;

			std::string keyStr(key.UTF8String);
			entry_t entry(keyStr);

			switch([typeNum intValue])
			{
				case kArchiveEntryTypeFile:
				{
					entry.set_type(entry_type_t::file);
					if(NSNumber* mod = node[kEntryModifiedKey]; [mod isKindOfClass:NSNumber.class])
						entry.set_modified((time_t)[mod longLongValue]);

					NSData* blob = node[kEntryContentKey];
					if([blob isKindOfClass:NSData.class] && blob.length > 0)
					{
						CFPropertyListRef cfPlist = CFPropertyListCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)blob, kCFPropertyListImmutable, nullptr, nullptr);
						if(cfPlist)
						{
							entry.set_content(plist::convert(cfPlist));
							CFRelease(cfPlist);
						}
					}
					break;
				}
				case kArchiveEntryTypeDirectory:
				{
					entry.set_type(entry_type_t::directory);
					if(NSString* glob = node[kEntryGlobKey]; [glob isKindOfClass:NSString.class])
						entry.set_glob_string(glob.UTF8String);
					if(NSNumber* eid = node[kEntryEventIdKey]; [eid isKindOfClass:NSNumber.class])
						entry.set_event_id((uint64_t)[eid unsignedLongLongValue]);

					std::vector<std::string> v;
					if(NSArray* childEntries = node[kEntryEntriesKey]; [childEntries isKindOfClass:NSArray.class])
					{
						for(id obj in childEntries)
						{
							if([obj isKindOfClass:NSString.class])
								v.emplace_back([(NSString*)obj UTF8String]);
						}
					}
					entry.set_entries(v);
					break;
				}
				case kArchiveEntryTypeLink:
				{
					entry.set_type(entry_type_t::link);
					if(NSString* link = node[kEntryLinkKey]; [link isKindOfClass:NSString.class])
						entry.set_link(link.UTF8String);
					break;
				}
				case kArchiveEntryTypeMissing:
				{
					entry.set_type(entry_type_t::missing);
					break;
				}
			}

			if(entry.type() != entry_type_t::unknown)
				_cache.emplace(keyStr, entry);
		}
	}

	void cache_t::save (std::string const& path) const
	{
		@autoreleasepool {
			NSMutableDictionary* entries = [NSMutableDictionary dictionaryWithCapacity:_cache.size()];
			for(auto const& pair : _cache)
			{
				entry_t const& entry = pair.second;
				NSMutableDictionary* node = [NSMutableDictionary dictionary];

				if(entry.is_file())
				{
					node[kEntryTypeKey]     = @(kArchiveEntryTypeFile);
					node[kEntryModifiedKey] = @((int64_t)entry.modified());

					if(CFPropertyListRef cfPlist = plist::create_cf_property_list(entry.content()))
					{
						if(CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault, cfPlist, kCFPropertyListBinaryFormat_v1_0, 0, nullptr))
						{
							node[kEntryContentKey] = (__bridge_transfer NSData*)data;
						}
						CFRelease(cfPlist);
					}
				}
				else if(entry.is_directory())
				{
					node[kEntryTypeKey]    = @(kArchiveEntryTypeDirectory);
					node[kEntryGlobKey]    = [NSString stringWithUTF8String:entry.glob_string().c_str()];
					node[kEntryEventIdKey] = @(entry.event_id());

					NSMutableArray* childArr = [NSMutableArray arrayWithCapacity:entry.entries().size()];
					for(auto const& p : entry.entries())
						[childArr addObject:[NSString stringWithUTF8String:p.c_str()]];
					node[kEntryEntriesKey] = childArr;
				}
				else if(entry.is_link())
				{
					node[kEntryTypeKey] = @(kArchiveEntryTypeLink);
					node[kEntryLinkKey] = [NSString stringWithUTF8String:entry.link().c_str()];
				}
				else if(entry.is_missing())
				{
					node[kEntryTypeKey] = @(kArchiveEntryTypeMissing);
				}
				else
				{
					continue;
				}

				NSString* key = [NSString stringWithUTF8String:pair.first.c_str()];
				if(key)
					entries[key] = node;
			}

			NSDictionary* archive = @{
				kArchiveVersionKey: @(kPropertyCacheFormatVersion),
				kArchiveEntriesKey: entries,
			};

			NSError* error = nil;
			NSData* data = nil;
			if(@available(macOS 10.13, *))
				data = [NSKeyedArchiver archivedDataWithRootObject:archive requiringSecureCoding:YES error:&error];
			if(!data)
			{
				os_log_error(OS_LOG_DEFAULT, "Failed to archive bundles cache: %{public}s", error.localizedDescription.UTF8String ?: "unknown");
				return;
			}

			NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
			[data writeToFile:nsPath atomically:YES];
		}
	}

	uint64_t cache_t::event_id_for_path (std::string const& path) const
	{
		auto it = _cache.find(path);
		return it == _cache.end() ? 0 : it->second.event_id();
	}

	void cache_t::set_event_id_for_path (uint64_t eventId, std::string const& path)
	{
		auto it = _cache.find(path);
		if(it != _cache.end() && it->second.event_id() != eventId)
		{
			it->second.set_event_id(eventId);
			_dirty = true;
		}
	}

	plist::dictionary_t cache_t::content (std::string const& path)
	{
		auto it = _cache.find(path);
		if(it != _cache.end() && it->second.type() == entry_type_t::missing)
		{
			os_log_error(OS_LOG_DEFAULT, "Content requested for missing item: ‘%{public}s’", path.c_str());
			_cache.erase(it);
		}
		return resolved(path).content();
	}

	std::vector<std::string> cache_t::entries (std::string const& path, std::string const& globString)
	{
		entry_t& entry = resolved(path, globString);

		std::vector<std::string> res;
		for(auto path : entry.entries())
			res.emplace_back(path::join(entry.path(), path));
		return res;
	}

	bool cache_t::erase (std::string const& path)
	{
		auto first = _cache.find(path);
		if(first == _cache.end())
			return false;

		if(first->second.is_directory())
		{
			auto parent = _cache.find(path::parent(path));
			if(parent != _cache.end() && parent->second.is_directory())
			{
				std::vector<std::string> entries = parent->second.entries();
				auto name = std::find(entries.begin(), entries.end(), path::name(path));
				if(name != entries.end())
				{
					entries.erase(name);
					parent->second.set_entries(entries, parent->second.glob_string());
				}
			}
			_cache.erase(first, _cache.lower_bound(path + "0")); // path + "0" is the first non-descendent
		}
		else
		{
			_cache.erase(first);
		}

		_dirty = true;
		return true;
	}

	bool cache_t::reload (std::string const& path, bool recursive)
	{
		bool dirty = false;
		auto it = _cache.find(path);
		if(it == _cache.end())
			return path::is_absolute(path) && path != "/" ? reload(path::parent(path), recursive) : dirty;

		struct stat buf;
		if(lstat(path.c_str(), &buf) == 0)
		{
			if(S_ISDIR(buf.st_mode) && it->second.is_directory())
			{
				auto oldEntries = recursive ? std::vector<std::string>() : it->second.entries();
				update_entries(it->second, it->second.glob_string());
				auto newEntries = it->second.entries();
				dirty = oldEntries != newEntries;
				for(auto name : newEntries)
				{
					auto entryIter = _cache.find(path::join(path, name));
					if(entryIter != _cache.end() && (entryIter->second.is_file() || recursive))
						dirty = reload(path::join(path, name), recursive) || dirty;
				}
			}
			else if(!(it->second.is_file() && S_ISREG(buf.st_mode) && it->second.modified() == buf.st_mtimespec.tv_sec))
			{
				_cache.erase(it);
				dirty = true;
			}
		}
		else if(!it->second.is_missing())
		{
			_cache.erase(it);
			dirty = true;
		}

		_dirty = _dirty || dirty;
		return dirty;
	}

	bool cache_t::cleanup (std::vector<std::string> const& rootPaths)
	{
		std::set<std::string> allPaths, reachablePaths;
		std::transform(_cache.begin(), _cache.end(), std::inserter(allPaths, allPaths.end()), [](std::pair<std::string, entry_t> const& pair){ return pair.first; });
		for(auto path : rootPaths)
			copy_all(path, std::inserter(reachablePaths, reachablePaths.end()));

		std::vector<std::string> toRemove;
		std::set_difference(allPaths.begin(), allPaths.end(), reachablePaths.begin(), reachablePaths.end(), back_inserter(toRemove));

		for(auto path : toRemove)
			_cache.erase(path);
		_dirty = _dirty || !toRemove.empty();
		return !toRemove.empty();
	}

	// ============================
	// = Private Member Functions =
	// ============================

	cache_t::entry_t& cache_t::resolved (std::string const& path, std::string const& globString)
	{
		auto it = _cache.find(path);
		if(it == _cache.end())
		{
			entry_t entry(path);
			entry.set_type(entry_type_t::missing);

			struct stat buf;
			if(lstat(path.c_str(), &buf) == 0)
			{
				if(S_ISREG(buf.st_mode))
				{
					entry.set_type(entry_type_t::file);
				}
				else if(S_ISLNK(buf.st_mode))
				{
					entry.set_type(entry_type_t::link);
					entry.set_link(read_link(path));
				}
				else if(S_ISDIR(buf.st_mode))
				{
					entry.set_type(entry_type_t::directory);
				}
			}

			if(entry.is_file())
			{
				auto const content = plist::load(path);
				entry.set_content(_prune_dictionary ? _prune_dictionary(content) : content);
				entry.set_modified(buf.st_mtimespec.tv_sec);
			}
			else if(entry.is_directory())
			{
				update_entries(entry, globString);
			}

			it = _cache.emplace(path, entry).first;
			_dirty = true;
		}
		return it->second.is_link() ? resolved(it->second.resolved(), globString) : it->second;
	}

	void cache_t::update_entries (entry_t& entry, std::string const& globString)
	{
		std::vector<std::string> entries;
		for(auto dirEntry : path::entries(entry.path(), globString))
			entries.emplace_back(dirEntry->d_name);
		std::sort(entries.begin(), entries.end());
		entry.set_entries(entries, globString);
	}

} /* plist */
