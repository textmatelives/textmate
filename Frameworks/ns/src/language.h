#ifndef NS_LANGUAGE_H_8KQ2V7XD
#define NS_LANGUAGE_H_8KQ2V7XD

namespace ns
{
	struct language_run_t
	{
		size_t first, last;   // byte offsets into the text
		std::string language; // BCP 47 tag, e.g. ‘en’ or ‘zh-Hans’
	};

	// Identifies the language of each run of ‘text’: a run is a stretch of one
	// script within one sentence. Runs are contiguous; text before the first
	// word (or that was left undetermined) belongs to no run.
	std::vector<language_run_t> identify_languages (std::string const& text);

	// The key of ‘localizations’ (language tags) that best matches the user’s
	// preferred languages, falling back to ‘en’ and then to the first key.
	std::string preferred_localization (std::vector<std::string> const& localizations);

} /* ns */

#endif /* end of include guard: NS_LANGUAGE_H_8KQ2V7XD */
