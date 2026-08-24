# rave: require text cf io plist OakSystem regexp, libraries curl,
#       frameworks SystemConfiguration Security
#
# Not present in tectiv3/textmate — they removed the in-app updater and this
# framework with it. Retained here because SoftwareUpdate depends on it.
add_library(network STATIC)
file(GLOB _src src/*.cc src/*.mm)
target_sources(network PRIVATE ${_src})
# Deliberately NOT textmate_framework(network).
#
# That helper exports build/include/<target> to every consumer, and this
# framework's directory is named "network". On a case-insensitive filesystem
# that shadows Apple's Network.framework for any translation unit that pulls it
# in transitively — which the force-included PCH does via Cocoa — producing
# errors inside our own constants.h.
#
# rave avoided this by precompiling the PCH once, before the framework include
# directories existed. Nothing outside Frameworks/network/tests actually
# includes <network/...>, so the directory is scoped to the test target below
# rather than exported tree-wide.
set(NETWORK_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/include")
if(NOT EXISTS "${NETWORK_INCLUDE_DIR}/network")
  file(MAKE_DIRECTORY "${NETWORK_INCLUDE_DIR}")
  file(CREATE_LINK "${CMAKE_CURRENT_SOURCE_DIR}/src" "${NETWORK_INCLUDE_DIR}/network" SYMBOLIC)
endif()
target_link_libraries(network PUBLIC
  text cf io plist OakSystem regexp -lcurl
  "-framework SystemConfiguration" "-framework Security")

# src/network.cc holds nothing but an __attribute__((constructor)) that calls
# curl_global_init. rave linked object files directly, so it was always
# present; linking a static archive instead, the member has no referenced
# symbol and the linker drops it, leaving libcurl to initialise itself lazily
# on first use, which libcurl documents as not thread-safe. Force the whole
# archive in so the constructor survives.
target_link_options(network INTERFACE
  "LINKER:-force_load,$<TARGET_FILE:network>")

textmate_add_tests(network)
if(TARGET network_tests)
  target_include_directories(network_tests PRIVATE "${NETWORK_INCLUDE_DIR}")
endif()
