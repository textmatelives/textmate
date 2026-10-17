# QuickLook.tmbundle — provenance

Frozen grammar + theme subset for the sandboxed Quick Look extensions,
which cannot read the user's `~/Library/Application Support/TextMate`
(see `Frameworks/quicklook`).

## Source

Every file here is a verbatim copy from TextMate's stock Managed Bundles
(`~/Library/Application Support/TextMate/Managed/Bundles`), taken
2026-10-17. No file contains user customizations.

Verify against recorded checksums:

    shasum -a 256 -c MANIFEST.sha256

Or re-verify against local managed bundles with:

    M=~/Library/Application\ Support/TextMate/Managed/Bundles
    for f in Syntaxes/* Themes/*; do
      find "$M" -name "$(basename "$f")" -exec cmp -s "$f" {} \; \
        -print -quit | grep -q . || echo "MODIFIED: $f"
    done

- `Syntaxes/` (44 files): curated language subset. Grammars referenced only
  via `include` by other snapshot grammars (e.g. fenced code blocks in
  Markdown) degrade gracefully when absent — see extension log
  ("include not found").
- `Themes/`: `Mac Classic.tmTheme` (light) and `Undead.tmTheme` (dark),
  both stock from `Themes.tmbundle`. The preview extension picks one based
  on the system appearance; there is intentionally no user-theme support.

## Maintenance

- To add a language: copy the stock grammar file here and rebuild. Prefer
  stock over customized copies; note any deliberate deviation in this file.
- Staleness is accepted and visible: highlighting follows this snapshot,
  not the user's installed bundles. Do not "fix" that with a sync
  mechanism without an architecture review (see textmate#131).
