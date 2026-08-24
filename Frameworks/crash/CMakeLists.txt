# rave: no deps
add_library(crash STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc)
target_sources(crash PRIVATE ${_src})
textmate_framework(crash)
