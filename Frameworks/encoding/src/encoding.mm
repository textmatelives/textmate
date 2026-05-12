#include "encoding.h"

namespace encoding
{
	// Curated subset of charsets that ICU (via Foundation) can detect. Order is
	// not significant; callers should not depend on it. See the ICU detection
	// guide: https://unicode-org.github.io/icu/userguide/conversion/detection.html
	std::vector<std::string> charsets ()
	{
		return {
			"UTF-8",
			"ISO-8859-1",
			"ISO-8859-2",
			"WINDOWS-1252",
			"MACROMAN",
			"CP932",
			"GB18030",
			"BIG5",
		};
	}

	std::string detect (char const* first, char const* last)
	{
		if(first == last)
			return "UTF-8";

		NSData* data = [NSData dataWithBytesNoCopy:(void*)first length:last - first freeWhenDone:NO];

		// Foundation's stringEncodingForData: returns 0 if no encoding could
		// be inferred (e.g. for an empty data object or random binary).
		NSStringEncoding enc = [NSString stringEncodingForData:data encodingOptions:nil convertedString:NULL usedLossyConversion:NULL];
		if(enc == 0)
			return "";

		CFStringEncoding cfEnc = CFStringConvertNSStringEncodingToEncoding(enc);
		CFStringRef name = CFStringConvertEncodingToIANACharSetName(cfEnc);
		if(!name)
			return "";

		NSString* upper = [(__bridge NSString*)name uppercaseString];
		return std::string(upper.UTF8String);
	}

	double probability (char const* first, char const* last, std::string const& charset)
	{
		return detect(first, last) == charset ? 1.0 : 0.0;
	}

} /* encoding */
