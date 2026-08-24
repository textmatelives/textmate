add_library(xdiff STATIC)

file(GLOB _src CONFIGURE_DEPENDS src/*.c)
target_sources(xdiff PRIVATE ${_src})

# This tree includes it as <xdiff/xdiff.h> (rave's convention), where tectiv3
# rewrote the callers to <xdiff.h>. Use the same symlink trick as the
# frameworks so the sources need no change and rave keeps working.
textmate_framework(xdiff)
target_include_directories(xdiff PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")

target_compile_options(xdiff PRIVATE
  -Wno-sign-compare
  -Wno-shorten-64-to-32
  -Wno-unused-function)
