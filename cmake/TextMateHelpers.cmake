# cmake/TextMateHelpers.cmake
# Custom build functions for TextMate's CMake build system.

# Framework include path setup.
# Source tree uses flat layout (src/buffer.h) but consumers
# include <buffer/buffer.h>. Symlink: build/include/<target>/ → src/
function(textmate_framework TARGET)
  set(_link "${CMAKE_CURRENT_BINARY_DIR}/include/${TARGET}")
  if(NOT EXISTS "${_link}")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include")
    file(CREATE_LINK
      "${CMAKE_CURRENT_SOURCE_DIR}/src"
      "${_link}"
      SYMBOLIC)
  endif()
  # INTERFACE, not PUBLIC: rave never puts a framework's own include directory
  # on its own compile line — only on its consumers'. That matters because
  # Frameworks/network symlinks to <network>, and on a case-insensitive
  # filesystem that shadows Apple's Network.framework for anything that pulls
  # it in transitively (the force-included PCH does). Keeping it off the
  # framework's own compile line reproduces rave's behaviour exactly.
  target_include_directories(${TARGET} INTERFACE "${CMAKE_CURRENT_BINARY_DIR}/include")
endfunction()

# Xib compilation (.xib → .nib via ibtool)
function(target_xib_sources TARGET RESOURCE_LOCATION)
  foreach(_xib ${ARGN})
    get_filename_component(_name "${_xib}" NAME_WE)
    set(_nib "${CMAKE_CURRENT_BINARY_DIR}/${_name}.nib")
    if(IS_ABSOLUTE "${_xib}")
      set(_xib_abs "${_xib}")
    else()
      set(_xib_abs "${CMAKE_CURRENT_SOURCE_DIR}/${_xib}")
    endif()
    add_custom_command(
      OUTPUT "${_nib}"
      COMMAND xcrun ibtool --compile "${_nib}"
        --errors --warnings --notices
        --output-format human-readable-text
        "${_xib_abs}"
      DEPENDS "${_xib_abs}"
      COMMENT "Xib: ${_xib}")
    target_sources(${TARGET} PRIVATE "${_nib}")
    set_source_files_properties("${_nib}" PROPERTIES
      MACOSX_PACKAGE_LOCATION "Resources/${RESOURCE_LOCATION}")
  endforeach()
endfunction()

# Asset catalog compilation (.xcassets → .car via actool)
function(target_asset_catalog TARGET XCASSETS_DIR)
  file(GLOB_RECURSE _assets CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${XCASSETS_DIR}/*")
  set(_car "${CMAKE_CURRENT_BINARY_DIR}/Assets.car")
  add_custom_command(
    OUTPUT "${_car}"
    COMMAND xcrun actool --compile "${CMAKE_CURRENT_BINARY_DIR}"
      --errors --warnings --notices
      --output-format human-readable-text
      --minimum-deployment-target=${CMAKE_OSX_DEPLOYMENT_TARGET}
      --platform=macosx
      "${CMAKE_CURRENT_SOURCE_DIR}/${XCASSETS_DIR}"
    DEPENDS ${_assets}
    COMMENT "AssetCatalog: ${XCASSETS_DIR}")
  target_sources(${TARGET} PRIVATE "${_car}")
  set_source_files_properties("${_car}" PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources)
endfunction()

# Code signing with optional entitlements
function(textmate_codesign TARGET IDENTITY)
  cmake_parse_arguments(_CS "" "ENTITLEMENTS" "" ${ARGN})
  set(_flags --force --options runtime)
  if(CMAKE_BUILD_TYPE STREQUAL "Release")
    list(APPEND _flags --timestamp)
  else()
    list(APPEND _flags --timestamp=none)
  endif()
  if(_CS_ENTITLEMENTS)
    list(APPEND _flags --entitlements "${_CS_ENTITLEMENTS}")
  endif()
  add_custom_command(TARGET ${TARGET} POST_BUILD
    COMMAND xcrun codesign --sign "${IDENTITY}" ${_flags}
      "$<TARGET_BUNDLE_DIR:${TARGET}>"
    COMMENT "Codesign: ${TARGET}")
endfunction()

# Sign a plain executable or dylib (non-bundle) after it is built
function(textmate_codesign_file TARGET IDENTITY FILE_PATH)
  set(_flags --force --options runtime)
  if(CMAKE_BUILD_TYPE STREQUAL "Release")
    list(APPEND _flags --timestamp)
  else()
    list(APPEND _flags --timestamp=none)
  endif()
  add_custom_command(TARGET ${TARGET} POST_BUILD
    COMMAND xcrun codesign --sign "${IDENTITY}" ${_flags} "${FILE_PATH}"
    COMMENT "Codesign file: ${FILE_PATH}")
endfunction()

# Embed a target into an app bundle.
# Usage: textmate_embed(AppTarget DepTarget "Location/In/Bundle" [DIRECTORY])
# Without DIRECTORY: copies the single executable file.
# With DIRECTORY: copies the entire bundle directory.
function(textmate_embed APP_TARGET DEP_TARGET LOCATION)
  cmake_parse_arguments(_EMB "DIRECTORY" "" "" ${ARGN})
  add_dependencies(${APP_TARGET} ${DEP_TARGET})
  if(_EMB_DIRECTORY)
    # Use rsync to preserve the bundle directory name (cmake copy_directory
    # copies contents, not the directory itself)
    add_custom_command(TARGET ${APP_TARGET} POST_BUILD
      COMMAND rsync -a
        "$<TARGET_BUNDLE_DIR:${DEP_TARGET}>"
        "$<TARGET_BUNDLE_DIR:${APP_TARGET}>/Contents/${LOCATION}/")
  else()
    add_custom_command(TARGET ${APP_TARGET} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy
        "$<TARGET_FILE:${DEP_TARGET}>"
        "$<TARGET_BUNDLE_DIR:${APP_TARGET}>/Contents/${LOCATION}/$<TARGET_FILE_NAME:${DEP_TARGET}>")
  endif()
endfunction()

# Test generation using bin/gen_test (Ruby script that generates runners
# from void test_*() and void benchmark_*() signatures)
function(textmate_add_tests FRAMEWORK_TARGET)
  if(NOT BUILD_TESTING)
    return()
  endif()
  file(GLOB _test_sources CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/t_*.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/t_*.mm")
  if(NOT _test_sources)
    return()
  endif()

  set(_test_target "${FRAMEWORK_TARGET}_tests")

  # Use .mm extension when any test source is ObjC++ so runner compiles correctly
  file(GLOB _mm_tests CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tests/t_*.mm")
  if(_mm_tests)
    set(_runner "${CMAKE_CURRENT_BINARY_DIR}/test_runner.mm")
    # rave ran every ObjC++ suite with --no-parallel, and bin/gen_test's serial
    # path runs on the main thread. Cocoa APIs that assert NSThread.isMainThread
    # abort otherwise — Frameworks/FileBrowser reaches TMFileReference through
    # SCMRepository and dies without this.
    set(_runner_args --no-parallel)
  else()
    set(_runner "${CMAKE_CURRENT_BINARY_DIR}/test_runner.cc")
    set(_runner_args "")
  endif()

  add_custom_command(
    OUTPUT "${_runner}"
    COMMAND "${CMAKE_SOURCE_DIR}/bin/gen_test" ${_test_sources} > "${_runner}"
    DEPENDS ${_test_sources} "${CMAKE_SOURCE_DIR}/bin/gen_test"
    COMMENT "gen_test: ${FRAMEWORK_TARGET}")

  # gen_test inlines test source bodies into the runner — don't compile them separately
  add_executable(${_test_target} "${_runner}")
  target_link_libraries(${_test_target} PRIVATE ${FRAMEWORK_TARGET} ${TEXTMATE_DEBUG_LIBS})
  target_include_directories(${_test_target} PRIVATE "${CMAKE_SOURCE_DIR}/Shared/include")
  add_test(NAME ${FRAMEWORK_TARGET} COMMAND ${_test_target} ${_runner_args})
  # CMake has no built-in "build every test" target, and ctest only runs
  # tests, it does not build them. Collect them under one target so CI can
  # build the suites without building the whole application.
  if(NOT TARGET tests)
    add_custom_target(tests)
  endif()
  add_dependencies(tests ${_test_target})

  # rave offered a `<framework>/test` target that built and ran one suite, and
  # .tm_properties still binds ⌘B on a test file to it. ctest can select a
  # single test but will not build it, so keep a target that does both.
  add_custom_target(${FRAMEWORK_TARGET}_test
    COMMAND "$<TARGET_FILE:${_test_target}>" ${_runner_args}
    DEPENDS ${_test_target}
    USES_TERMINAL
    VERBATIM)
endfunction()

# Markdown -> HTML via bin/gen_html (multimarkdown).
# Mirrors rave's CompileMarkdown rule. WRAP ON passes the header/footer
# templates, which is what rave did for every page it rendered, because
# MD_FLAGS was set on the whole TextMate target. WRAP OFF renders a bare
# fragment and is currently unused.
function(textmate_markdown TARGET SRC DEST_DIR WRAP)
  get_filename_component(_name "${SRC}" NAME_WE)
  set(_out "${CMAKE_CURRENT_BINARY_DIR}/md/${DEST_DIR}/${_name}.html")
  if(WRAP)
    set(_flags -h "${CMAKE_CURRENT_SOURCE_DIR}/templates/header.html"
               -f "${CMAKE_CURRENT_SOURCE_DIR}/templates/footer.html")
  else()
    set(_flags "")
  endif()
  add_custom_command(
    OUTPUT "${_out}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/md/${DEST_DIR}"
    COMMAND "${CMAKE_SOURCE_DIR}/bin/gen_html" ${_flags} "${SRC}" > "${_out}"
    DEPENDS "${SRC}" "${CMAKE_SOURCE_DIR}/bin/gen_html"
    # Contributions.md does `require File.join(File.dirname(__FILE__),
    # 'bin/gen_credits')`, which resolves relative to the working directory.
    # rave invoked gen_html from the repo root, so do the same.
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Markdown ${_name}.html"
    VERBATIM)
  target_sources(${TARGET} PRIVATE "${_out}")
  set_source_files_properties("${_out}" PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources/${DEST_DIR}" GENERATED TRUE)
endfunction()

# Copy a directory tree into the bundle at build time, preserving layout.
function(textmate_copy_tree TARGET SRC_DIR DEST)
  set(_dst "$<TARGET_BUNDLE_DIR:${TARGET}>/Contents/${DEST}")
  add_custom_command(TARGET ${TARGET} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${SRC_DIR}" "${_dst}"
    # rave's `copy` skipped dotfiles; copy_directory does not, which would
    # otherwise ship each bundle's .sha marker.
    COMMAND find "${_dst}" -name ".*" -delete
    COMMENT "Copying ${DEST}"
    VERBATIM)
endfunction()

# .strings -> expanded + UTF-16, mirroring rave's ExpandVariables followed by
# ConvertToUTF16. Reusing bin/expand_variables is what keeps the output
# byte-identical: it preserves the source's UTF-16 byte order and adds no
# trailing newline, neither of which configure_file or a plain iconv pipeline
# gets right.
function(textmate_strings TARGET SRC DEST_DIR)
  get_filename_component(_name "${SRC}" NAME)
  # Keyed on the target: two targets in one directory (the Dialog plug-ins)
  # would otherwise claim the same output path.
  set(_dir "${CMAKE_CURRENT_BINARY_DIR}/strings/${TARGET}/${DEST_DIR}")
  set(_expanded "${_dir}/expanded-${_name}")
  set(_out "${_dir}/${_name}")
  string(TIMESTAMP _year "%Y")
  add_custom_command(
    OUTPUT "${_out}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_dir}"
    COMMAND "${CMAKE_SOURCE_DIR}/bin/expand_variables" -o "${_expanded}"
            "-dYEAR=${_year}" "-dTARGET_NAME=${TARGET}"
            "-dAPP_MIN_OS=${CMAKE_OSX_DEPLOYMENT_TARGET}" "${SRC}"
    # rave's ConvertToUTF16 passes through anything that already carries a
    # UTF-16 BOM, which is how the plug-in strings keep their little-endian
    # byte order; iconv would re-encode them as big-endian.
    COMMAND sh -c "if [ \"$(head -c2 '${_expanded}' | xxd -p)\" = fffe ] || [ \"$(head -c2 '${_expanded}' | xxd -p)\" = feff ]; then cp '${_expanded}' '${_out}'; else iconv -f utf-8 -t utf-16 < '${_expanded}' > '${_out}'; fi"
    DEPENDS "${SRC}" "${CMAKE_SOURCE_DIR}/bin/expand_variables"
    COMMENT "Strings ${_name}"
    VERBATIM)
  target_sources(${TARGET} PRIVATE "${_out}")
  set_source_files_properties("${_out}" PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources/${DEST_DIR}" GENERATED TRUE)
endfunction()
