#ifndef ENCODING_H_3OJVUZM1
#define ENCODING_H_3OJVUZM1

namespace encoding
{
	std::vector<std::string> charsets ();
	double probability (char const* first, char const* last, std::string const& charset);
	std::string detect (char const* first, char const* last);

} /* encoding */

#endif /* end of include guard: ENCODING_H_3OJVUZM1 */
