#!/bin/sh
#
# Reset TextMate managed bundles to local repo checkouts via symlinks.
# Removes the downloaded Ruby 1.8.7 installation.
#
# Usage: ./bin/reset_bundles.sh

set -e

MANAGED="$HOME/Library/Application Support/TextMate/Managed/Bundles"
REPOS="$HOME/src/github.com/textmatelives/bundles"
SUPPORT_REPO="$HOME/src/github.com/textmatelives/bundle-support.tmbundle"

# Map managed bundle directory names to repo directory names
map_name() {
  case "$1" in
    "Bundle Support")  echo "SUPPORT" ;;
    "Shell Script")    echo "shellscript" ;;
    "SCM Diff Gutter") echo "scm-diff-gutter" ;;
    "Hyperlink Helper") echo "hyperlink-helper" ;;
    "Bundle Development") echo "bundle-development" ;;
    "Property List")   echo "property-list" ;;
    "Objective-C")     echo "objective-c" ;;
    *)                 echo "$1" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

# Remove downloaded Ruby 1.8.7
if [ -d "$HOME/Library/Application Support/TextMate/Ruby" ]; then
  echo "Removing Ruby 1.8.7 installation..."
  rm -rf "$HOME/Library/Application Support/TextMate/Ruby"
fi

# Replace managed bundles with symlinks
for bundle in "$MANAGED"/*.tmbundle; do
  [ -d "$bundle" ] || continue
  name=$(basename "$bundle" .tmbundle)
  repo_name=$(map_name "$name")

  if [ "$repo_name" = "SUPPORT" ]; then
    target="$SUPPORT_REPO"
  else
    target="$REPOS/$repo_name.tmbundle"
  fi

  if [ ! -d "$target" ]; then
    echo "SKIP $name (no repo at $target)"
    continue
  fi

  echo "Linking $name -> $target"
  rm -rf "$bundle"
  ln -s "$target" "$bundle"
done

echo "Done."
