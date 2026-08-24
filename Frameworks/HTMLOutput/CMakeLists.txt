add_library(HTMLOutput STATIC)
file(GLOB_RECURSE _src src/*.mm)
target_sources(HTMLOutput PRIVATE ${_src})
textmate_framework(HTMLOutput)

# rave's `headers` directive flattens nested headers, so consumers write
#   #import <HTMLOutput/OakHTMLOutputRequestMetadata.h>
# even though the file lives in src/helpers/. tectiv3 rewrote those imports to
# <HTMLOutput/helpers/...>; that would break the rave build, which still has to
# work while the migration lands. Expose the flat name via a second include
# root instead, and leave the sources alone.
set(_flat_include "${CMAKE_CURRENT_BINARY_DIR}/include-flat/HTMLOutput")
file(MAKE_DIRECTORY "${_flat_include}")
if(NOT EXISTS "${_flat_include}/OakHTMLOutputRequestMetadata.h")
  file(CREATE_LINK
    "${CMAKE_CURRENT_SOURCE_DIR}/src/helpers/OakHTMLOutputRequestMetadata.h"
    "${_flat_include}/OakHTMLOutputRequestMetadata.h" SYMBOLIC)
endif()
target_include_directories(HTMLOutput PUBLIC "${CMAKE_CURRENT_BINARY_DIR}/include-flat")
target_link_libraries(HTMLOutput PUBLIC
  OakAppKit OakFoundation OakSystem cf document io ns text "-framework Cocoa" "-framework WebKit" "-framework UniformTypeIdentifiers")

textmate_add_tests(HTMLOutput)
