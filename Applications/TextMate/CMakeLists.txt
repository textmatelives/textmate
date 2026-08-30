add_executable(TextMate MACOSX_BUNDLE)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc src/*.mm)
target_sources(TextMate PRIVATE ${_src})

# Internal framework dependencies
target_link_libraries(TextMate PRIVATE
  BundleEditor BundleMenu BundlesManager CommitWindow DocumentWindow
  Find HTMLOutputWindow MenuBuilder OakAppKit OakCommand OakFilterList OakFoundation
  OakSystem OakTextView Preferences authorization bundles cf command
  crash document io kvdb ns plist regexp scm settings text theme
  CrashReporter SoftwareUpdate network  # retained here; removed in tectiv3
  ${TEXTMATE_DEBUG_LIBS}
)

target_link_libraries(TextMate PRIVATE "-framework Cocoa" "-framework UniformTypeIdentifiers")

# Info.plist variable expansion. Info.plist names the app through
# ${TARGET_NAME} — CFBundleName is ${TARGET_NAME}, CFBundleIdentifier is
# com.macromates.${TARGET_NAME} — so that is the only variable the expansion
# reads.
#
# A BUNDLE_IDENTIFIER/BUNDLE_NAME pair giving non-Release builds a
# "com.macromates.TextMate-dev" identity came across with the CMake migration
# but was never referenced here, so it has never had any effect: every build,
# local or CI, has identified as com.macromates.TextMate. It is not restored,
# deliberately. Applications/mate looks the app up by a hardcoded
# com.macromates.TextMate (mate.mm), so a separate development identity would
# quietly point `mate` at whatever stable build is installed instead of the one
# being debugged, and would ask for its own TCC grants. Both cost more than the
# preference isolation they would buy. Nothing shipped is affected either way:
# CI configures Release (release.yml, build-and-test.yml), and Application
# Support is pinned to "TextMate" in main.mm regardless of CFBundleName.
set(TARGET_NAME "TextMate")
set(APP_MIN_OS "${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(APP_VERSION "${TEXTMATE_VERSION}")
string(TIMESTAMP YEAR "%Y")
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(CS_GET_TASK_ALLOW "true")
else()
  set(CS_GET_TASK_ALLOW "false")
endif()
configure_file(Info.plist ${CMAKE_CURRENT_BINARY_DIR}/Info.plist)

# Expand ${YEAR} in InfoPlist.strings and encode it as UTF-16, the way rave did.
textmate_strings(TextMate
  "${CMAKE_CURRENT_SOURCE_DIR}/resources/English.lproj/InfoPlist.strings"
  "English.lproj")
set_target_properties(TextMate PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

# Compile xib → nib (all xibs from TextMate and frameworks go into the app bundle)
target_xib_sources(TextMate "English.lproj"
  resources/English.lproj/MainMenu.xib
  "${CMAKE_SOURCE_DIR}/Frameworks/OakTextView/resources/English.lproj/TabSizeSetting.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/Preferences/resources/English.lproj/TerminalPreferences.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/English.lproj/CustomizeEncodings.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/English.lproj/Pasteboard Selector.xib")
target_xib_sources(TextMate "English.lproj"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/BundleProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/FileDropProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/CommandProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/SharedProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/SnippetProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/ThemeProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/MacroProperties.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/resources/English.lproj/GrammarProperties.xib")

# Icon and image resources
file(GLOB _icons CONFIGURE_DEPENDS icons/*.icns)
# resources/* excluding "TextMate Help" and English.lproj: the Help directory
# is rendered from Markdown below (globbing it here would also copy the .md
# sources into the bundle) and the xibs are compiled to .nib separately.
file(GLOB _resources CONFIGURE_DEPENDS resources/*)
list(FILTER _resources EXCLUDE REGEX "/(TextMate Help|English\\.lproj|textmate_lives\\.icon)$")
set(_all_resources ${_icons} ${_resources})
target_sources(TextMate PRIVATE ${_all_resources})
set_source_files_properties(${_all_resources} PROPERTIES
  MACOSX_PACKAGE_LOCATION Resources)

# Framework resources (static libs can't carry resources, so they go in the app bundle)
file(GLOB _fw_res CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/Frameworks/Preferences/icons/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakTextView/resources/*.pdf"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakTextView/resources/*.tiff"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakTextView/resources/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/gfx/CloseButton/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/Charsets.plist"
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/gfx/Bundle Item Icons/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakTabBarView/gfx/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/FileBrowser/resources/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/DocumentWindow/resources/*.png"
  "${CMAKE_SOURCE_DIR}/Frameworks/HTMLOutput/resources/*.html"
  "${CMAKE_SOURCE_DIR}/Frameworks/HTMLOutput/resources/*.js"
  "${CMAKE_SOURCE_DIR}/Frameworks/scm/resources/*.xslt"
)
target_sources(TextMate PRIVATE ${_fw_res})
set_source_files_properties(${_fw_res} PROPERTIES
  MACOSX_PACKAGE_LOCATION Resources)

# TMFileReference resources go in Resources/DocumentTypes/ subdirectory
file(GLOB _doctype_res CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/Frameworks/TMFileReference/resources/*.icns"
  "${CMAKE_SOURCE_DIR}/Frameworks/TMFileReference/resources/bindings.plist")
target_sources(TextMate PRIVATE ${_doctype_res})
set_source_files_properties(${_doctype_res} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/DocumentTypes")

# About window: Markdown is converted at build time by bin/gen_html, as rave
# did. tectiv3 committed pre-converted HTML instead; this tree keeps generating
# it so CHANGELOG.md edits cannot go stale.
foreach(_md about/About.md about/Contributions.md about/Legal.md)
  textmate_markdown(TextMate "${CMAKE_CURRENT_SOURCE_DIR}/${_md}" "About" ON)
endforeach()
textmate_markdown(TextMate "${CMAKE_SOURCE_DIR}/CHANGELOG.md" "About" ON)

# The Help pages get the same header/footer treatment: rave's MD_FLAGS is set
# on the whole TextMate target, so every .md it converts is wrapped.
file(GLOB _help_md CONFIGURE_DEPENDS "resources/TextMate Help/*.md")
foreach(_md ${_help_md})
  textmate_markdown(TextMate "${_md}" "TextMate Help" ON)
endforeach()

file(GLOB _help_css CONFIGURE_DEPENDS "resources/TextMate Help/css/*")
file(GLOB _help_img CONFIGURE_DEPENDS "resources/TextMate Help/images/*")
target_sources(TextMate PRIVATE ${_help_css} ${_help_img})
set_source_files_properties(${_help_css} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/TextMate Help/css")
set_source_files_properties(${_help_img} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/TextMate Help/images")

file(GLOB _about_css CONFIGURE_DEPENDS about/css/*)
file(GLOB _about_js CONFIGURE_DEPENDS about/js/*)
target_sources(TextMate PRIVATE ${_about_css} ${_about_js})
set_source_files_properties(${_about_css} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/About/css")
set_source_files_properties(${_about_js} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/About/js")

# Framework resources: rave's per-target `files resources/* "Resources"`.
file(GLOB _fw_res CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/Frameworks/BundleEditor/templates/*.plist"
  "${CMAKE_SOURCE_DIR}/Frameworks/SoftwareUpdate/resources/*"
  "${CMAKE_SOURCE_DIR}/Frameworks/scm/resources/*")
target_sources(TextMate PRIVATE ${_fw_res})
set_source_files_properties(${_fw_res} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")

# Bundled tmbundles — rave's `copy support/* "SharedSupport"`.
textmate_copy_tree(TextMate "${CMAKE_CURRENT_SOURCE_DIR}/support" "SharedSupport")

# Assets.car — rave transforms resources/textmate_lives.icon via actool.
target_asset_catalog(TextMate "resources/textmate_lives.icon")

# Embedded CLI tools
textmate_embed(TextMate mate "MacOS")
textmate_embed(TextMate tm_query "MacOS")
textmate_embed(TextMate CommitWindowTool "MacOS")
textmate_embed(TextMate PrivilegedTool "Resources")

# Embedded plugins (.tmplugin bundles from submodules)
textmate_embed(TextMate Dialog "PlugIns" DIRECTORY)
textmate_embed(TextMate Dialog2 "PlugIns" DIRECTORY)

# Embedded QuickLook plugin
textmate_embed(TextMate TextMateQL "Library/QuickLook" DIRECTORY)

# Sign embedded binaries (inner-to-outer, before app signature)
textmate_codesign_file(TextMate "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:TextMate>/Contents/MacOS/mate")
textmate_codesign_file(TextMate "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:TextMate>/Contents/MacOS/tm_query")
textmate_codesign_file(TextMate "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:TextMate>/Contents/MacOS/CommitWindowTool")
textmate_codesign_file(TextMate "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:TextMate>/Contents/Resources/PrivilegedTool")

# Entitlements + code signing (outer app — must be last)
configure_file(Entitlements.plist ${CMAKE_CURRENT_BINARY_DIR}/Entitlements.plist)
textmate_codesign(TextMate "${CS_IDENTITY}"
  ENTITLEMENTS "${CMAKE_CURRENT_BINARY_DIR}/Entitlements.plist")

# `ninja run` builds, signs and relaunches TextMate, the way rave's
# `TextMate/run` target did. .tm_properties points ⌘B at it.
add_custom_target(run
  COMMAND "${CMAKE_SOURCE_DIR}/bin/relaunch_app" "$<TARGET_BUNDLE_DIR:TextMate>"
  USES_TERMINAL
  VERBATIM)
add_dependencies(run TextMate)
