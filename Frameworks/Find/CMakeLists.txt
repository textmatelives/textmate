add_library(Find STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc src/*.mm)
target_sources(Find PRIVATE ${_src})
textmate_framework(Find)
target_link_libraries(Find PUBLIC
  MenuBuilder OakAppKit OakFoundation Preferences bundles document io ns regexp scope settings text
  "-framework Cocoa")

textmate_add_tests(Find)
