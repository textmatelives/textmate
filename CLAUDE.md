# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork constraints

This is `textmatelives/textmate`, a fork of `textmate/textmate` targeting macOS 26 / Apple Silicon.

Hard constraints declared by the maintainer:
- arm64 only — do not add x86_64 fallbacks
- System Ruby 2.6.10 only — no bundled Rubies, no downloads, no 1.8 compatibility code
- Forward compatible (macOS 26+); zero traces of Ruby 1.8 anywhere

## Build system

CMake generating Ninja. The root `CMakeLists.txt` sets the shared compiler
configuration and adds one subdirectory per framework, application and plug-in;
`cmake/TextMateHelpers.cmake` holds the project-specific functions
(`textmate_framework`, `target_xib_sources`, `target_asset_catalog`,
`textmate_codesign`, `textmate_embed`, `textmate_markdown`, `textmate_strings`,
`textmate_add_tests`).

The compiler config is C++20, ObjC ARC, deployment target 14.0
(`CMakeLists.txt:1-30`). Precompiled headers live in `Shared/PCH/prelude.{c,cc,m,mm}`
and are force-included per language. `NULL_STR` is passed via `-D`. The legacy
`REST_API` macro (formerly `https://api.textmate.org`) was removed in PR #9; the
fork makes no `api.textmate.org` calls (see "Bundle delivery" below).

Common commands:

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # First-time configure
ninja -C build TextMate            # Build and sign TextMate.app
ninja -C build run                 # Build, sign, gracefully relaunch TextMate.app
ninja -C build tests               # Build every framework test suite
ninja -C build <Framework>_test    # Build and run one suite (e.g. scm_test)
ctest --test-dir build             # Run all suites and report together
```

The app lands at `build/Applications/TextMate/TextMate.app`. To clean, delete
the build directory. Signing uses an ad-hoc identity unless `-DCS_IDENTITY=...`
is passed.

Two things the old rave build got for free and CMake does not, both already
handled — do not undo them. rave linked object files directly, so an
`__attribute__((constructor))` in an otherwise-unreferenced translation unit
always ran. CMake links static archives, where the linker drops such a member
outright. `vendor/Onigmo/src/setup.c` (Unicode-aware `\w`, `\b`, `\p{...}`
everywhere) and `Frameworks/network/src/network.cc` (`curl_global_init`) are
both pulled in with `-force_load` for that reason. Anything else added with a
constructor and no referenced symbol needs the same treatment.

`.tm_properties` sets `TM_NINJA_TARGET` rules so ⌘B inside TextMate auto-picks
the right target: editing `tests/t_*.{cc,mm}` builds and runs `<framework>_test`;
editing under `Applications/<X>/` builds `<X>`; otherwise `run`. It expects the
build directory to be `build` inside the source tree.

## Architecture

Objective-C++. Low-level data structures and parsing are C++; AppKit/Cocoa surfaces are ObjC++ wrapping the C++ types. See `INTERNALS.md` for the buffer/layout/tree internals.

The two largest layers worth knowing:

- **Text core** — `Frameworks/buffer` (`ng::buffer_t`: text storage, lines, scopes, marks), `Frameworks/layout` (`ng::layout_t`: visual layout + drawing), `Frameworks/OakTextView` (`OakTextView`, `GutterView`, `OakDocumentView`). All built on `oak::basic_tree_t`, an AA-tree with binary-indexed offsets.
- **SCM** — Two-tier. `Frameworks/scm` (C++ `scm::shared_info_t`, `scm::info_t`, drivers under `src/drivers/`) does the actual `git status` work behind a per-instance dispatch queue and an FSEvents watcher. `Frameworks/FileBrowser/src/SCMManager.mm` (`SCMRepository`) is the ObjC consumer that subscribes via `info_t::push_callback`. The C++ side is the source of truth — do not reintroduce a parallel ObjC subsystem that re-runs git itself.

`Frameworks/HTMLOutput` was migrated from legacy `WebView` to `WKWebView` for macOS 26. The bundle-output bridge runs through three custom `WKURLSchemeHandler`s (`x-txmt-filehandle`, `tm-file`, `tm-system`) in `Frameworks/HTMLOutput/src/helpers/`. `tm-system` is the synchronous variant required by the git bundle's commit dialog.

## Tests

CxxTest-style, but home-grown: `bin/gen_test` reads each `tests/t_*.{cc,mm}` file, finds top-level `void test_*()` functions, and emits a single runner with `main()`. `textmate_add_tests` in `cmake/TextMateHelpers.cmake` wires that up and registers the suite with CTest. Assertions are `OAK_ASSERT`, `OAK_ASSERT_EQ`, `OAK_ASSERT_NE`. Filesystem fixtures use `test::jail_t` from `Frameworks/test`.

A framework opts in by calling `textmate_add_tests(<target>)` in its `CMakeLists.txt`; the helper picks up `tests/t_*.{cc,mm}` on its own. Run one via `ninja -C build <framework>_test`, or all of them via `ctest --test-dir build`.

Runner flags (parsed by the generated runner via `getopt_long`, `bin/gen_test:155-189`):
- `-v` verbose, `-m` measure, `-r N` repeat, `-b` benchmarks, `-p`/`-P` (`--parallel` / `--no-parallel`)

`.mm` test runners are passed `--no-parallel` automatically and `bin/gen_test` runs the serial path on the main thread when `--no-parallel` is set — required by Cocoa APIs that assert `NSThread.isMainThread` (e.g. `TMFileReference`). Pure C++ (`.cc`) runners stay parallel.

There is no name-based test filter. To run a subset, either run the test binary directly (`build/Frameworks/<name>/<name>_tests -v`) or temporarily edit the test source.

Tests that shell out to git must call `git init -b master` (not bare `git init`) — modern git's `init.defaultBranch` defaults to `main` and breaks tests that assume `master`.

## Bundle delivery

The fork uses forked bundles under `~/src/github.com/textmatelives/bundles/` and `bundle-support.tmbundle`, ported to Ruby 2.6.10. Local dev wires them in via symlinks in `~/Library/Application Support/TextMate/Managed/Bundles/` — `bin/reset_bundles.sh` performs that wiring.

The `REST_API` macro and its `api.textmate.org` source were removed in PR #9; bundle delivery is now git-URL/codeload-based (`BundlesManager.mm` fetches via `BundleFetcher` from `codeload.github.com`). `BundlesManager.mm` still polls every 3h via `NSBackgroundActivityScheduler`. The Managed/Bundles symlink approach side-steps this for development; packaging for distribution is unresolved.

Ruby in bundles resolves through `${TM_RUBY:-/usr/bin/ruby}` via `Support/shared/bin/ruby` in the forked `bundle-support.tmbundle`. `TM_RUBY` is the long-standing override hook — do not introduce a new Ruby discovery scheme.
