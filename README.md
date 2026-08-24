# TextMate

<p align="center">
  <img src="docs/images/tml_banner_800px.png" alt="TextMate Lives" width="1000">
</p>

## About this fork

I ❤️ TextMate.

I have been using it almost everyday since I bought it (way back in I think 2008?) and while many friends and colleagues moved on to Sublime, then Atom then VS Code etc. I stayed with TextMate. I just like TextMate. Even with its many quirks over the last few years, I stuck with it -- it is a trusted ally. I still think when it comes to editing, it has features that many folks fail to appreciate.

I have always wanted to contribute and help get it back up to speed, but to be honest, I am not much of a macOS programmer and TextMate is a fairly sophisticated app. You can probably see where this is heading: *vibe coded fixes.*

Now, I recognize that some folks may not be keen on this practice and so I make no assumptions or prognostications and I will not storm Allan Odgaard with unsolicited PRs, but I have a bunch of changes that I think could help put TM back in a great place for the other folks out there that still enjoy using it.

@sorbits if you are still out there, thank you for TextMate. I hope that this message finds you well and that you do not find the work distasteful or offensive.

Long live TextMate!

## Requirements

- Apple Silicon (arm64); Intel Macs are not supported.
- macOS 26 or later.
- System Ruby 2.6.10 (`/usr/bin/ruby`) for bundle commands. Override with `TM_RUBY` if needed.

## Download

Grab the latest signed and notarized build from the [Releases page](https://github.com/textmatelives/textmate/releases).

## Feedback

For fork-specific bugs, feature requests, and discussion, [file an issue](https://github.com/textmatelives/textmate/issues). Patches are welcome too — [open a pull request](https://github.com/textmatelives/textmate/pulls), with or without a matching issue.

For questions about TextMate proper (history, design, upstream behaviour), see the [upstream project](https://github.com/textmate/textmate).

## Screenshot

<p align="center">
  <img src="docs/images/screenshot_undead.png" alt="textmate" width="1000">
</p>

# Building

## Setup

To build TextMate, you need the following:

 * [cmake][]         — build system generator
 * [multimarkdown][] — marked-up plain text compiler
 * [ninja][]         — build system similar to `make`

All this can be installed using either [Homebrew][] or [MacPorts][]:

```sh
# Homebrew
brew install cmake multimarkdown ninja

# MacPorts
sudo port install cmake multimarkdown ninja
```

Running the `scm` test suite additionally needs `git`, `hg` and `svn` on the
`PATH`.

After installing dependencies, make sure you have a full checkout (including
submodules), then configure a build directory and build it:

```sh
git clone --recursive https://github.com/textmatelives/textmate.git
cd textmate
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --target TextMate
```

The result is `build/Applications/TextMate/TextMate.app`. Configuring is only
needed once; afterwards `ninja -C build` is enough, and it re-runs CMake by
itself when a `CMakeLists.txt` changes.

Builds are signed with an ad-hoc signature by default. To sign with a real
identity, pass its name or hash: `-DCS_IDENTITY="Developer ID Application: …"`.

## Building from within TextMate

You should install the [Ninja][NinjaBundle] bundle which can be installed via
_Preferences_ → _Bundles_.

After this you can press ⌘B to build from within TextMate. In case you haven't
already you also need to set up the `PATH` variable either in _Preferences_ →
_Variables_ or `~/.tm_properties` so it can find `ninja` and related tools; an
example could be `$PATH:/opt/homebrew/bin`.

`.tm_properties` expects the build directory to be `build` inside the source
tree, which is what the `cmake -B build` line above creates.

The default target is `run`. This will relaunch TextMate, but when called from
within TextMate a dialog will appear before the current instance is killed. As
there is full session restore, it is safe to relaunch even with unsaved
changes.

If the current file is a test file then the target is changed to the one that
builds and runs the suite it belongs to, and if the current file belongs to an
application target other than `TextMate.app` then that application is built
instead.

## Build Targets

```sh
ninja -C build TextMate   # Build and sign TextMate
ninja -C build run        # Build, sign, and (re)launch TextMate
ninja -C build tests      # Build every framework test suite
ninja -C build io_test    # Build and run one suite (here: Frameworks/io)
```

Test suites are also registered with CTest, which runs them and reports
results together:

```sh
cmake --build build --target tests
ctest --test-dir build --output-on-failure
```

To clean everything, delete the `build` directory.

# Legal

The source for TextMate is released under the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

TextMate is a trademark of Allan Odgaard.

[cmake]:         https://cmake.org/
[ninja]:         https://ninja-build.org/
[multimarkdown]: http://fletcherpenney.net/multimarkdown/
[MacPorts]:      http://www.macports.org/
[Homebrew]:      http://brew.sh/
[NinjaBundle]:   https://github.com/textmate/ninja.tmbundle
