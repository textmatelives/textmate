add_library(encoding STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(encoding PRIVATE ${_src})
textmate_framework(encoding)

textmate_add_tests(encoding)
