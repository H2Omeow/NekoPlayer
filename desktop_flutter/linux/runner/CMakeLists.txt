cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "desktop_integration.cc"
  "crash_handler.cc"
  "lyrics_view.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
pkg_check_modules(FONTCONFIG REQUIRED IMPORTED_TARGET fontconfig)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::FONTCONFIG)
target_link_libraries(${BINARY_NAME} PRIVATE ${CMAKE_DL_LIBS})

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Crash diagnostics: -rdynamic/-g1 give readable symbols in native backtraces.
target_compile_options(${BINARY_NAME} PRIVATE -g1)
target_link_options(${BINARY_NAME} PRIVATE -rdynamic)
