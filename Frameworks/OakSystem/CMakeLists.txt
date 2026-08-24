# rave: require cf io text
add_library(OakSystem STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc)
target_sources(OakSystem PRIVATE ${_src})
textmate_framework(OakSystem)
target_link_libraries(OakSystem PUBLIC cf io text)
