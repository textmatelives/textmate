#ifndef NS_LANGUAGE_H_8KQ2V7XD
#define NS_LANGUAGE_H_8KQ2V7XD

namespace ns
{
	// The key of ‘localizations’ (language tags) that best matches the user’s
	// preferred languages, falling back to ‘en’ and then to the first key.
	std::string preferred_localization (std::vector<std::string> const& localizations);

} /* ns */

#endif /* end of include guard: NS_LANGUAGE_H_8KQ2V7XD */
