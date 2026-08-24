# The two Dialog plug-ins live in submodules (github.com/textmate/dialog and
# github.com/textmate/dialog-1.x) that this repository does not control, so
# their build rules live here in the parent rather than inside the submodule
# checkouts, where they could not be committed.

# Expands ${TARGET_NAME} in a plug-in's Info.plist, which CMake does not do
# for MACOSX_BUNDLE_INFO_PLIST.
function(_dialog_info_plist TARGET SRC_DIR)
  set(TARGET_NAME "${TARGET}")
  set(_out "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}/Info.plist")
  configure_file("${SRC_DIR}/Info.plist" "${_out}")
  set_target_properties(${TARGET} PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${_out}")
endfunction()

# === dialog: tm_dialog2 and Dialog2.tmplugin ===

set(_dialog "${CMAKE_CURRENT_SOURCE_DIR}/dialog")

add_executable(tm_dialog2 "${_dialog}/tm_dialog2.mm")
target_link_libraries(tm_dialog2 PRIVATE "-framework Foundation")

# Listed explicitly rather than globbed. rave used Ruby's Dir.glob, where
# Commands/**/*.mm also matches Commands/*.mm; CMake's file(GLOB) does not,
# and silently dropped the seven top-level command implementations.
add_library(Dialog2 MODULE
  "${_dialog}/CLIProxy.mm"
  "${_dialog}/Dialog2.mm"
  "${_dialog}/TMDCommand.mm"
  "${_dialog}/Commands/alert.mm"
  "${_dialog}/Commands/defaults.mm"
  "${_dialog}/Commands/filepanel.mm"
  "${_dialog}/Commands/help.mm"
  "${_dialog}/Commands/images.mm"
  "${_dialog}/Commands/insert.mm"
  "${_dialog}/Commands/menu.mm"
  "${_dialog}/Commands/Utilities/TextMate.mm"
  "${_dialog}/Commands/Utilities/ValueTransformers.mm"
  "${_dialog}/Commands/nib/nib.mm"
  "${_dialog}/Commands/nib/TMDNibController.mm"
  "${_dialog}/Commands/popup/popup.mm"
  "${_dialog}/Commands/popup/TMDIncrementalPopUpMenu.mm"
  "${_dialog}/Commands/prototype/prototype.mm"
  "${_dialog}/Commands/prototype/TMDChameleon.mm"
  "${_dialog}/Commands/tooltip/tooltip.mm"
  "${_dialog}/Commands/tooltip/TMDHTMLTips.mm")

set_target_properties(Dialog2 PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "tmplugin")
_dialog_info_plist(Dialog2 "${_dialog}")

target_link_options(Dialog2 PRIVATE -bundle)
target_link_libraries(Dialog2 PRIVATE
  "-framework Cocoa" "-framework WebKit" "-framework Quartz")

# Embed tm_dialog2 in the plug-in's Resources, then sign inner to outer.
add_dependencies(Dialog2 tm_dialog2)
add_custom_command(TARGET Dialog2 POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy
    "$<TARGET_FILE:tm_dialog2>"
    "$<TARGET_BUNDLE_DIR:Dialog2>/Contents/Resources/tm_dialog2")
textmate_codesign_file(Dialog2 "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:Dialog2>/Contents/Resources/tm_dialog2")
textmate_codesign(Dialog2 "${CS_IDENTITY}")

textmate_strings(Dialog2 "${_dialog}/English.lproj/InfoPlist.strings" "English.lproj")

# === dialog-1.x: tm_dialog and Dialog.tmplugin ===

set(_dialog1 "${CMAKE_CURRENT_SOURCE_DIR}/dialog-1.x")

add_executable(tm_dialog "${_dialog1}/tm_dialog.mm")
target_link_libraries(tm_dialog PRIVATE "-framework Foundation")

# ValueTransformers.mm sits beside these but is not in dialog-1.x's rave
# sources, so it is left out here too.
add_library(Dialog MODULE
  "${_dialog1}/Dialog.mm"
  "${_dialog1}/TMDChameleon.mm"
  "${_dialog1}/TMDSemaphore.mm")

set_target_properties(Dialog PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "tmplugin")
_dialog_info_plist(Dialog "${_dialog1}")

target_link_options(Dialog PRIVATE -bundle)
target_link_libraries(Dialog PRIVATE "-framework Cocoa")

add_dependencies(Dialog tm_dialog)
add_custom_command(TARGET Dialog POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy
    "$<TARGET_FILE:tm_dialog>"
    "$<TARGET_BUNDLE_DIR:Dialog>/Contents/Resources/tm_dialog")
textmate_codesign_file(Dialog "${CS_IDENTITY}"
  "$<TARGET_BUNDLE_DIR:Dialog>/Contents/Resources/tm_dialog")
textmate_codesign(Dialog "${CS_IDENTITY}")

textmate_strings(Dialog "${_dialog1}/English.lproj/InfoPlist.strings" "English.lproj")
