#ifndef SCM_GIT_PARSE_H_2WCRPPW
#define SCM_GIT_PARSE_H_2WCRPPW

#include <map>
#include <string>
#include "../status.h"

namespace scm { namespace git_parse {

	// Resolve the XY status pair from `git status --porcelain=v1` to a single
	// `scm::status::type`. Conflict (any U, or AA, or DD) dominates; otherwise
	// the index column (X) is preferred over the worktree column (Y) for the
	// resolved verb. ' ' (space) means "unchanged" in that column. Returns
	// scm::status::none when both are clean, or scm::status::unknown for an
	// unrecognised pair.
	scm::status::type resolve_porcelain_xy (char X, char Y);

	// Parse `git status --porcelain=v1 -z` output, writing path → status pairs
	// into `entries`. Existing keys are overwritten. Output may be NULL_STR.
	//
	// Renames/copies are recorded as add+delete to match the existing
	// `parse_diff` behaviour (which has no rename concept): the new path takes
	// the resolved status, and the original path is recorded as
	// scm::status::deleted.
	void parse_porcelain (std::map<std::string, scm::status::type>& entries,
	                      std::string const& output);

} /* git_parse */ } /* scm */

#endif /* end of include guard */
