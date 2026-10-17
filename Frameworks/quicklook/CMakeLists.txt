# Shared Quick Look highlight core: index a bundles directory, render a file to
# a highlighted NSAttributedString. Used by the Preview and Thumbnail app
# extensions (sandboxed: touches only the paths it is given, never the home dir).
add_library(quicklook STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(quicklook PRIVATE ${_src})
textmate_framework(quicklook)
target_link_libraries(quicklook PUBLIC
  OakFoundation buffer bundles cf file io ns plist scope settings theme OakDebug
  "-framework AppKit" "-framework Foundation" "-framework OSAKit")

textmate_add_tests(quicklook)
