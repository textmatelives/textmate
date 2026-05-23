#!/usr/bin/env bash
# Compile an Icon Composer .icon bundle to Assets.car via actool.
#
# Two modes:
#   build_app_icon.sh                 # default: src + dst hard-coded to the
#                                     # textmate_lives.icon under Applications/
#                                     # TextMate. Convenient for manual regen.
#   build_app_icon.sh <src> <out>     # explicit: ninja invokes this form via
#                                     # the CompileIcon rule in bin/rave.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ge 2 ]]; then
	src=$1
	out=$2
else
	src="$repo_root/Applications/TextMate/resources/textmate_lives.icon"
	out="$repo_root/Applications/TextMate/resources/Assets.car"
fi

if [[ ! -d $src ]]; then
	echo >&2 "build_app_icon.sh: missing source: $src"
	exit 1
fi

icon_name=$(basename "$src" .icon)
mkdir -p "$(dirname "$out")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xcrun actool \
	--compile "$tmp" \
	--platform macosx \
	--minimum-deployment-target 26.0 \
	--app-icon "$icon_name" \
	--output-partial-info-plist "$tmp/partial.plist" \
	--output-format human-readable-text \
	"$src" >/dev/null

cp "$tmp/Assets.car" "$out"
