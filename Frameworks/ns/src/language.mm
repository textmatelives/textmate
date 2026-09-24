#import "language.h"
#import "ns.h"

namespace ns
{
	std::string preferred_localization (std::vector<std::string> const& localizations)
	{
		if(localizations.empty())
			return NULL_STR;

		NSMutableArray* available = [NSMutableArray array];
		for(auto const& tag : localizations)
			[available addObject:to_ns(tag)];

		NSString* best = [NSBundle preferredLocalizationsFromArray:available forPreferences:NSLocale.preferredLanguages].firstObject;
		if(best && std::find(localizations.begin(), localizations.end(), to_s(best)) != localizations.end())
			return to_s(best);
		if(std::find(localizations.begin(), localizations.end(), "en") != localizations.end())
			return "en";
		return localizations.front();
	}

} /* ns */
