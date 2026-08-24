# rave: require text
add_library(OakFoundation STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(OakFoundation PRIVATE ${_src})
textmate_framework(OakFoundation)
target_link_libraries(OakFoundation PUBLIC text "-framework Cocoa")
textmate_add_tests(OakFoundation)
