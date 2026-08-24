add_library(BundlesManager STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.cc src/*.mm)
target_sources(BundlesManager PRIVATE ${_src})
textmate_framework(BundlesManager)
target_link_libraries(BundlesManager PUBLIC
  SoftwareUpdate  # retained here; removed in tectiv3
  OakAppKit OakFoundation bundles io ns regexp text "-framework Foundation" "-framework Security")

textmate_add_tests(BundlesManager)
