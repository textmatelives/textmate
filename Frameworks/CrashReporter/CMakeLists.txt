# rave: require Preferences, frameworks Foundation UserNotifications,
#       libraries z
#
# Not present in tectiv3/textmate — they removed the crash reporter.
add_library(CrashReporter STATIC)
file(GLOB _src CONFIGURE_DEPENDS src/*.mm)
target_sources(CrashReporter PRIVATE ${_src})
textmate_framework(CrashReporter)
target_link_libraries(CrashReporter PUBLIC
  Preferences -lz "-framework Foundation" "-framework UserNotifications")
