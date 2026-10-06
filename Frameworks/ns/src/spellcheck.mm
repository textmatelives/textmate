#import "spellcheck.h"

#import <OakFoundation/NSString Additions.h>
#import <text/utf16.h>
#import <os/log.h>

namespace ns
{
	long int spelling_tag_t::helper_t::tag ()
	{
		if(!_did_setup)
		{
			if(CFRunLoopGetCurrent() != CFRunLoopGetMain())
			{
				dispatch_semaphore_t sem = dispatch_semaphore_create(0);
				CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
					_tag = [NSSpellChecker uniqueSpellDocumentTag];
					_did_setup = true;
					dispatch_semaphore_signal(sem);
				});
				CFRunLoopWakeUp(CFRunLoopGetMain());
				dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
			}
			else
			{
				_tag = [NSSpellChecker uniqueSpellDocumentTag];
				_did_setup = true;
			}
		}
		return _tag;
	}

	spelling_tag_t::helper_t::~helper_t ()
	{
		if(_did_setup)
		{
			NSInteger tag = _tag;
			CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
				@autoreleasepool {
					[NSSpellChecker.sharedSpellChecker closeSpellDocumentWithTag:tag];
				}
			});
		}
	}

	// Returns false when AppleSpell timed out. The caller leaves the rest of
	// the buffer unchecked. Issue #101.
	template <typename _OutputIter>
	bool spellcheck (char const* first, char const* last, std::string const& language, long int tag, size_t offset, _OutputIter out)
	{
		NSSpellChecker* spellChecker = NSSpellChecker.sharedSpellChecker;
		NSString* lang               = language.length() ? [NSString stringWithCxxString:language] : nil;
		NSString* str                = [NSString stringWithUTF8String:first length:last - first];
		NSInteger start              = 0;

		for(;;)
		{
			NSRange range = { NSNotFound, 0 };
			@try {
				range = [spellChecker checkSpellingOfString:str startingAt:start language:lang wrap:NO inSpellDocumentWithTag:tag wordCount:NULL];
			}
			@catch(NSException* exception) {
				if(![exception.name isEqualToString:@"NSXPCSpellServerTimeoutException"])
					@throw;
				os_log_error(OS_LOG_DEFAULT, "Skipping spell check: %{public}@", exception.reason);
				return false;
			}

			if(range.location == NSNotFound || range.length == 0)
				return true;

			char const* from = utf16::advance(first, range.location, last);
			char const* to   = utf16::advance(from,  range.length,   last);
			*out++ = ns::range_t(offset + from - first, offset + to - first);
			start = NSMaxRange(range);
		}
	}

	std::vector<ns::range_t> spellcheck (char const* first, char const* last, std::string const& language, spelling_tag_t const& tag)
	{
		std::vector<ns::range_t> res;
		@autoreleasepool {
			size_t offset = 0;
			for(char const* it = first; it != last; )
			{
				char const* eol = std::find(it, last, '\n');
				if(!spellcheck(it, eol, language, tag, offset, back_inserter(res)))
					break;
				while(eol != last && *eol == '\n')
					++eol;
				offset += eol - it;
				it = eol;
			}
		}
		return res;
	}

	bool is_misspelled (char const* first, char const* last, std::string const& language, spelling_tag_t const& tag)
	{
		return !spellcheck(first, last, language, tag).empty();
	}

} /* ns */
