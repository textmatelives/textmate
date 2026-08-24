add_library(HTMLOutputWindow STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(HTMLOutputWindow PRIVATE ${_src})
textmate_framework(HTMLOutputWindow)
target_link_libraries(HTMLOutputWindow PUBLIC HTMLOutput OakAppKit OakFoundation command ns
  "-framework Cocoa")
