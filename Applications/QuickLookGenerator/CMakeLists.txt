# .qlgenerator bundle, not a regular app
add_library(TextMateQL MODULE)
file(GLOB _src src/*.c src/*.mm)
target_sources(TextMateQL PRIVATE ${_src})

# Info.plist refers to ${TARGET_NAME}, which rave's expand_variables filled in.
# CMake only substitutes its own MACOSX_BUNDLE_* variables into a bundle plist,
# so ${TARGET_NAME} would come out empty — leaving CFBundleExecutable blank and
# CFBundleIdentifier as "com.macromates.". Configure it ourselves instead.
set(TARGET_NAME TextMateQL)
configure_file(Info.plist "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

set_target_properties(TextMateQL PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "qlgenerator"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

target_link_options(TextMateQL PRIVATE -bundle)
target_link_libraries(TextMateQL PRIVATE
  OakFoundation buffer bundles cf file io ns plist scope settings theme OakDebug
  "-framework CoreFoundation" "-framework QuickLook" "-framework AppKit" "-framework OSAKit" "-framework UniformTypeIdentifiers")

textmate_codesign(TextMateQL "${CS_IDENTITY}")

# rave propagates a framework's `files resources/* "Resources"` into every
# target that requires it, so TextMateQL picks up OakAppKit's and scm's
# resources as well as its own. CMake has no equivalent, so list them.
file(GLOB _ql_res
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/Charsets.plist"
  "${CMAKE_SOURCE_DIR}/Frameworks/scm/resources/svn_status.xslt"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/gfx/CloseButton/*.png")
target_sources(TextMateQL PRIVATE ${_ql_res})
set_source_files_properties(${_ql_res} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")

target_xib_sources(TextMateQL "English.lproj"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/English.lproj/CustomizeEncodings.xib"
  "${CMAKE_SOURCE_DIR}/Frameworks/OakAppKit/resources/English.lproj/Pasteboard Selector.xib")
