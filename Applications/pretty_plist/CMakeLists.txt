add_executable(pretty_plist)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc)
target_sources(pretty_plist PRIVATE ${_src})
target_link_libraries(pretty_plist PRIVATE plist ${TEXTMATE_DEBUG_LIBS})
