cmake_minimum_required(VERSION 3.21)
project(TextMate LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_C_STANDARD 99)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

# ObjC flags — one flag per generator expression
add_compile_options(
  $<$<COMPILE_LANGUAGE:OBJC>:-fobjc-abi-version=3>
  $<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>
  $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-abi-version=3>
  $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
  $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-call-cxx-cdtors>
)

# Common flags (all languages) — from default.rave FLAGS
add_compile_options(
  -funsigned-char
  -Wall -Wwrite-strings -Wformat -Winit-self -Wmissing-include-dirs
  -Wno-parentheses -Wno-sign-compare -Wno-switch -Wno-c99-designator
)
# REST_API is not defined here: this fork has no callers (the updater moved to
# git's ref advertisement), unlike upstream and tectiv3.
add_compile_definitions(
  "NULL_STR=\"\\uFFFF\""
)

# Debug: -Os + ASan (rave debug config uses -Os)
set(CMAKE_C_FLAGS_DEBUG "-Os -g -fsanitize=address -fno-omit-frame-pointer" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "-Os -g -fsanitize=address -fno-omit-frame-pointer" CACHE STRING "" FORCE)
set(CMAKE_OBJC_FLAGS_DEBUG "-Os -g -fsanitize=address -fno-omit-frame-pointer" CACHE STRING "" FORCE)
set(CMAKE_OBJCXX_FLAGS_DEBUG "-Os -g -fsanitize=address -fno-omit-frame-pointer" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS_DEBUG "-fsanitize=address" CACHE STRING "" FORCE)

# Release: LTO + dead stripping
set(CMAKE_C_FLAGS_RELEASE "-Os -DNDEBUG -flto=thin" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-Os -DNDEBUG -flto=thin" CACHE STRING "" FORCE)
set(CMAKE_OBJC_FLAGS_RELEASE "-Os -DNDEBUG -flto=thin" CACHE STRING "" FORCE)
set(CMAKE_OBJCXX_FLAGS_RELEASE "-Os -DNDEBUG -flto=thin" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS_RELEASE
  "-flto=thin -Wl,-dead_strip -Wl,-dead_strip_dylibs -Wl,-cache_path_lto,${CMAKE_BINARY_DIR}/.lto-cache"
  CACHE STRING "" FORCE)

# ObjC runtime linking + force-load ObjC categories from static libraries
add_link_options(-fobjc-link-runtime -ObjC)

# Dependencies — none required (all external deps removed)

# Version, read from CHANGELOG.md — the same source rave used:
#   capture TEXTMATE_VERSION "grep -om1 '^## .* (v.*)$' ... | sed ..."
#
# Deliberately NOT tectiv3's `git describe` derivation: their regex is
# ^v([0-9]+\.[0-9]+[0-9.]*)(-([0-9]+))? which turns v2.1.5-undead into "2.1.5",
# silently dropping the suffix this fork ships under.
file(STRINGS "${CMAKE_SOURCE_DIR}/CHANGELOG.md" _changelog_lines)
set(TEXTMATE_VERSION "")
foreach(_line IN LISTS _changelog_lines)
  if(_line MATCHES "^## .* \\(v(.*)\\)$")
    set(TEXTMATE_VERSION "${CMAKE_MATCH_1}")
    break()
  endif()
endforeach()
if(TEXTMATE_VERSION STREQUAL "")
  message(FATAL_ERROR "No '## <date> (v<version>)' heading found in CHANGELOG.md")
endif()
message(STATUS "TextMate version: ${TEXTMATE_VERSION}")

# Shared includes
include_directories(Shared/include)

# Precompiled headers — force-include per language (matches rave's PCH behavior)
include_directories(Shared/PCH)
add_compile_options(
  $<$<COMPILE_LANGUAGE:C>:-include${CMAKE_SOURCE_DIR}/Shared/PCH/prelude.c>
  $<$<COMPILE_LANGUAGE:CXX>:-include${CMAKE_SOURCE_DIR}/Shared/PCH/prelude.cc>
  $<$<COMPILE_LANGUAGE:OBJC>:-include${CMAKE_SOURCE_DIR}/Shared/PCH/prelude.m>
  $<$<COMPILE_LANGUAGE:OBJCXX>:-include${CMAKE_SOURCE_DIR}/Shared/PCH/prelude.mm>
)

# Helpers
include(CTest)
include(cmake/TextMateHelpers.cmake)

# Code signing identity
set(CS_IDENTITY "-" CACHE STRING "Code signing identity (- for ad-hoc)")

# OakDebug provides oak::to_s and OakBadAssertion symbols used pervasively
# through header templates — needed in all build configs, not just debug
set(TEXTMATE_DEBUG_LIBS OakDebug)

# === Vendor ===
add_subdirectory(vendor/Onigmo)
add_subdirectory(vendor/kvdb)
add_subdirectory(vendor/xdiff)

# === Leaf Frameworks (no internal deps or only text) ===
add_subdirectory(Frameworks/text)
add_subdirectory(Frameworks/scope)
add_subdirectory(Frameworks/crash)
add_subdirectory(Frameworks/OakFoundation)
add_subdirectory(Frameworks/cf)
add_subdirectory(Frameworks/MenuBuilder)

# === Low-level frameworks ===
add_subdirectory(Frameworks/ns)
add_subdirectory(Frameworks/OakSystem)
add_subdirectory(Frameworks/OakDebug)
add_subdirectory(Frameworks/io)
add_subdirectory(Frameworks/authorization)
add_subdirectory(Frameworks/regexp)
add_subdirectory(Frameworks/encoding)

# === Core engine ===
add_subdirectory(Frameworks/parse)
add_subdirectory(Frameworks/bundles)
add_subdirectory(Frameworks/plist)
add_subdirectory(Frameworks/selection)
add_subdirectory(Frameworks/buffer)
add_subdirectory(Frameworks/undo)
add_subdirectory(Frameworks/editor)
add_subdirectory(Frameworks/settings)
add_subdirectory(Frameworks/theme)

# === Services ===
add_subdirectory(Frameworks/scm)
add_subdirectory(Frameworks/file)
add_subdirectory(Frameworks/command)
add_subdirectory(Frameworks/layout)

# === GUI frameworks ===
# Retained in this fork; removed in tectiv3 along with the in-app updater.
add_subdirectory(Frameworks/network)

# === GUI frameworks ===
add_subdirectory(Frameworks/OakAppKit)
add_subdirectory(Frameworks/TMFileReference)
add_subdirectory(Frameworks/Preferences)
add_subdirectory(Frameworks/OakTabBarView)
add_subdirectory(Frameworks/OakFilterList)
add_subdirectory(Frameworks/HTMLOutput)
add_subdirectory(Frameworks/HTMLOutputWindow)
add_subdirectory(Frameworks/OakCommand)
add_subdirectory(Frameworks/BundlesManager)
add_subdirectory(Frameworks/BundleMenu)
add_subdirectory(Frameworks/BundleEditor)
add_subdirectory(Frameworks/Find)
add_subdirectory(Frameworks/FileBrowser)
add_subdirectory(Frameworks/OakTextView)
add_subdirectory(Frameworks/document)
add_subdirectory(Frameworks/DocumentWindow)
add_subdirectory(Frameworks/CommitWindow)
add_subdirectory(Frameworks/SoftwareUpdate)
add_subdirectory(Frameworks/CrashReporter)

# === Applications ===
add_subdirectory(Applications/mate)
add_subdirectory(Applications/gtm)
add_subdirectory(Applications/indent)
add_subdirectory(Applications/pretty_plist)
add_subdirectory(Applications/tm_query)
add_subdirectory(Applications/PrivilegedTool)
add_subdirectory(Applications/QuickLookGenerator)
add_subdirectory(Applications/NewApplication)
add_subdirectory(Applications/TextMate)

# === PlugIns (submodules) ===
add_subdirectory(PlugIns/dialog)
add_subdirectory(PlugIns/dialog-1.x)
