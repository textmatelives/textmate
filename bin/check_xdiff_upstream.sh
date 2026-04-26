#!/bin/sh
#
# Check for upstream changes to xdiff/ since the SHA pinned in
# vendor/xdiff/VERSION. Reports new commits; does not modify the tree.
#
# Usage: bin/check_xdiff_upstream.sh
#

set -e

cd "$(dirname "$0")/.."
VERSION_FILE="vendor/xdiff/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
	echo "missing: $VERSION_FILE" >&2
	exit 1
fi

PINNED=$(awk '$1 == "commit:" { print $2 }' "$VERSION_FILE")
if [ -z "$PINNED" ]; then
	echo "could not parse pinned commit from $VERSION_FILE" >&2
	exit 1
fi

CACHE="${TMPDIR:-/tmp}/git-source.git"
if [ ! -d "$CACHE" ]; then
	echo "cloning git source into $CACHE (one-time, ~150MB)..."
	git clone --bare --filter=blob:none https://github.com/git/git.git "$CACHE"
else
	git -C "$CACHE" fetch --quiet origin
fi

echo "pinned:  $PINNED"
echo "tip:     $(git -C "$CACHE" rev-parse origin/master)"
echo

NEW=$(git -C "$CACHE" log --oneline "$PINNED..origin/master" -- xdiff/ 2>/dev/null || true)
if [ -z "$NEW" ]; then
	echo "no new commits to xdiff/ since pinned version."
else
	COUNT=$(printf '%s\n' "$NEW" | wc -l | tr -d ' ')
	echo "$COUNT new commits to xdiff/ since pinned version:"
	echo
	printf '%s\n' "$NEW"
fi
