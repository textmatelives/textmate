# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork constraints

This is `textmatelives/textmate`, a fork of `textmate/textmate` targeting macOS 26 / Apple Silicon.

Hard constraints declared by the maintainer:
- arm64 only — do not add x86_64 fallbacks
- System Ruby 2.6.10 only — no bundled Rubies, no downloads, no 1.8 compatibility code
- Forward compatible (macOS 26+); zero traces of Ruby 1.8 anywhere

## Build system

`./configure` checks dependencies (`capnp ninja ragel multimarkdown pgrep pkill`) and bootstraps `build.ninja` by invoking `bin/rave -crelease -tTextMate`. `bin/rave` is a Ruby DSL parser that walks `Applications/*/`, `Frameworks/*/`, `PlugIns/*/`, `vendor/*/` for `default.rave` files (see `default.rave:46`) and emits ninja rules. After `./configure`, all builds go through `ninja`.

The compiler config is C++20 (`-std=c++2a`), ObjC ARC, deployment target 10.12 (`default.rave:1-7`). Precompiled headers live in `Shared/PCH/prelude.{c,cc,m,mm}`. `NULL_STR` and `REST_API` are passed via `-D` (`default.rave:12`); `REST_API` is still hardcoded to `https://api.textmate.org` even though forked bundles bypass it (see "Bundle delivery" below).

Common commands:

```sh
./configure                        # First-time / regen build.ninja
ninja                              # Default target (TextMate, per ./configure -tTextMate)
ninja TextMate/run                 # Build, sign, gracefully relaunch TextMate.app
ninja -t clean                     # Or delete ~/build/TextMate
ninja <Framework>/test             # Run a framework's test suite (e.g. scm/test)
ninja <App>/run                    # Run any other app (e.g. mate/run)
```

`$builddir` defaults to `~/build/TextMate`. `bin/rave -b<dir>` overrides it.

`.tm_properties` sets `TM_NINJA_TARGET` rules so ⌘B inside TextMate auto-picks the right target: editing `tests/t_*.{cc,mm}` builds `<framework>/test`; editing under `Applications/<X>/` builds `<X>/run`; otherwise `TextMate/run`.

## Architecture

Objective-C++. Low-level data structures and parsing are C++; AppKit/Cocoa surfaces are ObjC++ wrapping the C++ types. See `INTERNALS.md` for the buffer/layout/tree internals.

The two largest layers worth knowing:

- **Text core** — `Frameworks/buffer` (`ng::buffer_t`: text storage, lines, scopes, marks), `Frameworks/layout` (`ng::layout_t`: visual layout + drawing), `Frameworks/OakTextView` (`OakTextView`, `GutterView`, `OakDocumentView`). All built on `oak::basic_tree_t`, an AA-tree with binary-indexed offsets.
- **SCM** — Two-tier. `Frameworks/scm` (C++ `scm::shared_info_t`, `scm::info_t`, drivers under `src/drivers/`) does the actual `git status` work behind a per-instance dispatch queue and an FSEvents watcher. `Frameworks/FileBrowser/src/SCMManager.mm` (`SCMRepository`) is the ObjC consumer that subscribes via `info_t::push_callback`. The C++ side is the source of truth — do not reintroduce a parallel ObjC subsystem that re-runs git itself.

`Frameworks/HTMLOutput` was migrated from legacy `WebView` to `WKWebView` for macOS 26. The bundle-output bridge runs through three custom `WKURLSchemeHandler`s (`x-txmt-filehandle`, `tm-file`, `tm-system`) in `Frameworks/HTMLOutput/src/helpers/`. `tm-system` is the synchronous variant required by the git bundle's commit dialog.

## Tests

CxxTest-style, but home-grown: `bin/gen_test` reads each `tests/t_*.{cc,mm}` file, finds top-level `void test_*()` functions, and emits a single runner with `main()` (`bin/rave:1372-1480`). Assertions are `OAK_ASSERT`, `OAK_ASSERT_EQ`, `OAK_ASSERT_NE`. Filesystem fixtures use `test::jail_t` from `Frameworks/test`.

Test files are declared in a framework's `default.rave` with `tests tests/t_*.{cc,mm}` (e.g. `Frameworks/scm/default.rave:7`, `Frameworks/FileBrowser/default.rave:7`). Run via `ninja <framework>/test`.

Runner flags (parsed by the generated runner via `getopt_long`, `bin/gen_test:155-189`):
- `-v` verbose, `-m` measure, `-r N` repeat, `-b` benchmarks, `-p`/`-P` (`--parallel` / `--no-parallel`)

`.mm` test runners are passed `--no-parallel` automatically (`bin/rave:1454`) and `bin/gen_test` runs the serial path on the main thread when `--no-parallel` is set — required by Cocoa APIs that assert `NSThread.isMainThread` (e.g. `TMFileReference`). Pure C++ (`.cc`) runners stay parallel.

There is no name-based test filter. To run a subset, either run the test binary directly (`~/build/TextMate/release/_Test/<id>/<name> -v`) or temporarily edit the test source.

Tests that shell out to git must call `git init -b master` (not bare `git init`) — modern git's `init.defaultBranch` defaults to `main` and breaks tests that assume `master`.

## Bundle delivery

The fork uses forked bundles under `~/src/github.com/textmatelives/bundles/` and `bundle-support.tmbundle`, ported to Ruby 2.6.10. Local dev wires them in via symlinks in `~/Library/Application Support/TextMate/Managed/Bundles/` — `bin/reset_bundles.sh` performs that wiring.

`REST_API` is still hardcoded at `default.rave:12` and `BundlesManager.mm` still polls every 3h via `NSBackgroundActivityScheduler`. The Managed/Bundles symlink approach side-steps this for development; packaging for distribution is unresolved.

Ruby in bundles resolves through `${TM_RUBY:-/usr/bin/ruby}` via `Support/shared/bin/ruby` in the forked `bundle-support.tmbundle`. `TM_RUBY` is the long-standing override hook — do not introduce a new Ruby discovery scheme.
