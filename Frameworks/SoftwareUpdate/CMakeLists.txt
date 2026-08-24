# rave: require OakAppKit, frameworks Cocoa WebKit
#
# Not present in tectiv3/textmate — they dropped the in-app updater in favour
# of GitHub Releases plus a Homebrew cask. Retained here: this tree ships a
# self-updating app.
#
# resources/Update Badge.tiff is copied into the bundle by
# Applications/TextMate/CMakeLists.txt, which is where framework resources are
# gathered, matching how the xibs are handled.
add_library(SoftwareUpdate STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(SoftwareUpdate PRIVATE ${_src})
textmate_framework(SoftwareUpdate)
target_link_libraries(SoftwareUpdate PUBLIC
  OakAppKit "-framework Cocoa" "-framework WebKit")

textmate_add_tests(SoftwareUpdate)
