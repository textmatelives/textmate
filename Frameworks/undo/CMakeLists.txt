# rave: require buffer selection
add_library(undo STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc)
target_sources(undo PRIVATE ${_src})
textmate_framework(undo)
target_link_libraries(undo PUBLIC buffer selection)
