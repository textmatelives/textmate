#import "language.h"
#import "ns.h"
#import <text/utf16.h>
#import <NaturalLanguage/NaturalLanguage.h>

namespace
{
	struct preferred_t
	{
		NSString* tag;      // as in NSLocale.preferredLanguages, e.g. ‘zh-Hans-CN’
		NSString* language; // its language subtag, e.g. ‘zh’
		NSString* variant;  // language and script, e.g. ‘zh-Hans’, or the language alone
	};

	std::vector<preferred_t> const& preferred_languages ()
	{
		static std::vector<preferred_t> const res = []{
			std::vector<preferred_t> res;
			for(NSString* tag in NSLocale.preferredLanguages)
			{
				NSDictionary* components = [NSLocale componentsFromLocaleIdentifier:tag];
				NSString* language = components[NSLocaleLanguageCode];
				NSString* script   = components[NSLocaleScriptCode];
				res.push_back({ tag, language, script ? [NSString stringWithFormat:@"%@-%@", language, script] : language });
			}
			return res;
		}();
		return res;
	}

	NSString* language_of (NLLanguage tag)
	{
		return [NSLocale componentsFromLocaleIdentifier:tag][NSLocaleLanguageCode];
	}

	// A short run rarely identifies with confidence, and variants of a language
	// even less so, so the user’s preferred languages settle what is uncertain:
	// the identified language in the user’s variant when it is one of theirs,
	// otherwise a confident identification, otherwise the first of theirs among the hypotheses.
	NSString* language_for_run (NLLanguageRecognizer* recognizer, NSString* run)
	{
		[recognizer reset];
		[recognizer processString:run];
		NSDictionary<NLLanguage, NSNumber*>* hypotheses = [recognizer languageHypothesesWithMaximum:10];
		NSArray<NLLanguage>* ranked = [hypotheses keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber* lhs, NSNumber* rhs){ return [rhs compare:lhs]; }];
		if(ranked.count == 0)
			return nil;

		auto const preferredVariant = [](NLLanguage tag) -> NSString* {
			NSString* language = language_of(tag);
			for(auto const& preferred : preferred_languages())
			{
				if([preferred.language isEqualToString:language])
					return preferred.variant;
			}
			return nil;
		};

		if(NSString* variant = preferredVariant(ranked.firstObject))
			return variant;
		if([hypotheses[ranked.firstObject] doubleValue] >= 0.9)
			return ranked.firstObject;
		for(NLLanguage tag in ranked)
		{
			if(NSString* variant = preferredVariant(tag))
				return variant;
		}
		return ranked.firstObject;
	}
}

namespace ns
{
	std::vector<language_run_t> identify_languages (std::string const& text)
	{
		std::vector<language_run_t> res;
		NSString* str = to_ns(text);
		if(str.length == 0)
			return res;

		// The NaturalLanguage objects are costly to create and kept for reuse,
		// one caller at a time.
		static std::mutex mutex;
		std::lock_guard<std::mutex> lock(mutex);
		static NLTokenizer* sentences = [[NLTokenizer alloc] initWithUnit:NLTokenUnitSentence];
		static NLTagger* scripts = [[NLTagger alloc] initWithTagSchemes:@[ NLTagSchemeScript ]];
		static NLLanguageRecognizer* recognizer = [[NLLanguageRecognizer alloc] init];

		sentences.string = str;
		scripts.string   = str;

		// Runs in UTF-16, before conversion to byte offsets.
		__block std::vector<std::pair<NSRange, NSString*>> runs;
		[sentences enumerateTokensInRange:NSMakeRange(0, str.length) usingBlock:^(NSRange sentence, NLTokenizerAttributes attrs, BOOL* stop){
			__block NSRange run = NSMakeRange(NSNotFound, 0);
			__block NLTag script = nil;
			auto const flush = ^{
				if(run.location != NSNotFound)
				{
					if(NSString* language = language_for_run(recognizer, [str substringWithRange:run]))
						runs.emplace_back(run, language);
				}
				run = NSMakeRange(NSNotFound, 0);
			};
			[scripts enumerateTagsInRange:sentence unit:NLTokenUnitWord scheme:NLTagSchemeScript options:NLTaggerOmitWhitespace|NLTaggerOmitPunctuation|NLTaggerOmitOther usingBlock:^(NLTag tag, NSRange word, BOOL* stop){
				if(!tag) // digits and the like belong to no script
					return;
				if(run.location != NSNotFound && [tag isEqualToString:script])
				{
					run.length = NSMaxRange(word) - run.location;
				}
				else
				{
					flush();
					run    = word;
					script = tag;
				}
			}];
			flush();
		}];

		// Make the runs contiguous: what follows a run (spaces, digits,
		// punctuation) is read in the same voice, and adjacent runs in the same
		// language become one.
		char const* base = text.data();
		char const* last = base + text.size();
		char const* it = base;
		NSUInteger offset = 0;
		auto const advance = [&](NSUInteger to){ it = utf16::advance(it, to - offset, last); offset = to; return size_t(it - base); };
		for(size_t i = 0; i < runs.size(); ++i)
		{
			size_t const first = advance(runs[i].first.location);
			size_t const end   = i + 1 < runs.size() ? advance(runs[i+1].first.location) : text.size();
			if(!res.empty() && res.back().language == to_s(runs[i].second))
					res.back().last = end;
			else	res.push_back({ first, end, to_s(runs[i].second) });
		}
		return res;
	}

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
