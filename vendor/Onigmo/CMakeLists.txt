add_library(Onigmo STATIC)

file(GLOB _src src/*.c)
file(GLOB _enc
  vendor/enc/ascii.c
  vendor/enc/euc_jp.c
  vendor/enc/iso8859_1.c
  vendor/enc/sjis.c
  vendor/enc/unicode.c
  vendor/enc/utf*.c)
file(GLOB _vendor vendor/reg*.c vendor/st.c)

target_sources(Onigmo PRIVATE ${_src} ${_enc} ${_vendor})

# Create symlink so <Onigmo/oniguruma.h> resolves
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include")
if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/include/Onigmo")
  file(CREATE_LINK
    "${CMAKE_CURRENT_SOURCE_DIR}/vendor"
    "${CMAKE_CURRENT_BINARY_DIR}/include/Onigmo"
    SYMBOLIC)
endif()
target_include_directories(Onigmo PUBLIC
  "${CMAKE_CURRENT_BINARY_DIR}/include")
target_include_directories(Onigmo PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/vendor")

# src/setup.c is nothing but an __attribute__((constructor)) that calls
# onig_init() and installs a Ruby syntax with ONIG_OPTION_ASCII_RANGE cleared,
# which is what makes \w, \b and \p{...} Unicode-aware everywhere in the
# editor. rave linked object files directly, so it always ran; linking a static
# archive instead, the member has no referenced symbol and the linker drops it,
# silently reverting every pattern to ASCII semantics. Force the whole archive
# in so the constructor survives.
target_link_options(Onigmo INTERFACE
  "LINKER:-force_load,$<TARGET_FILE:Onigmo>")

target_compile_options(Onigmo PRIVATE
  $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types>
  $<$<COMPILE_LANGUAGE:C>:-Wno-char-subscripts>)

textmate_add_tests(Onigmo)
