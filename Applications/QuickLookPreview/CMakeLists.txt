# Preview app extension (.appex), replacing the legacy .qlgenerator
add_executable(TextMateQLPreview MACOSX_BUNDLE)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(TextMateQLPreview PRIVATE ${_src})

set(TARGET_NAME TextMateQLPreview)
configure_file(Info.plist "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

set_target_properties(TextMateQLPreview PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "appex"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

# App extensions have no main(): enter through NSExtensionMain
target_link_options(TextMateQLPreview PRIVATE "LINKER:-e,_NSExtensionMain")

target_link_libraries(TextMateQLPreview PRIVATE
  quicklook
  "-framework Foundation" "-framework QuickLookUI" "-framework UniformTypeIdentifiers")

textmate_codesign(TextMateQLPreview "${CS_IDENTITY}"
  ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/QuickLookPreview.entitlements")

# Vendored grammar/theme snapshot (self-contained: the sandbox cannot reach the user's bundles)
file(GLOB _ql_syntax CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Bundles/QuickLook.tmbundle/Syntaxes/*")
file(GLOB _ql_themes CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Bundles/QuickLook.tmbundle/Themes/*")
set(_ql_info "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Bundles/QuickLook.tmbundle/info.plist")
target_sources(TextMateQLPreview PRIVATE ${_ql_syntax} ${_ql_themes} ${_ql_info})
set_source_files_properties(${_ql_syntax} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/Bundles/QuickLook.tmbundle/Syntaxes")
set_source_files_properties(${_ql_themes} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/Bundles/QuickLook.tmbundle/Themes")
set_source_files_properties(${_ql_info} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/Bundles/QuickLook.tmbundle")
