add_executable(gtm)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc)
target_sources(gtm PRIVATE ${_src})
target_link_libraries(gtm PRIVATE parse ${TEXTMATE_DEBUG_LIBS})
