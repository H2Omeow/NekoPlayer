cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "shell32.lib")
add_library(nekoplayer_desktop_integration STATIC "desktop_integration.cpp")
target_compile_features(nekoplayer_desktop_integration PRIVATE cxx_std_20)
target_compile_definitions(nekoplayer_desktop_integration PRIVATE NOMINMAX _HAS_EXCEPTIONS=1)
target_compile_options(nekoplayer_desktop_integration PRIVATE /EHsc /utf-8)
target_link_libraries(nekoplayer_desktop_integration PRIVATE flutter flutter_wrapper_app windowsapp gdi32 user32 shell32)
target_link_libraries(${BINARY_NAME} PRIVATE nekoplayer_desktop_integration)
add_library(nekoplayer_lyrics_view STATIC "lyrics_view.cpp")
target_compile_features(nekoplayer_lyrics_view PRIVATE cxx_std_20)
target_compile_definitions(nekoplayer_lyrics_view PRIVATE NOMINMAX _HAS_EXCEPTIONS=1)
target_compile_options(nekoplayer_lyrics_view PRIVATE /EHsc /utf-8)
target_link_libraries(nekoplayer_lyrics_view PUBLIC flutter flutter_wrapper_app PRIVATE shell32 ole32 user32)
if(NEKO_WEBVIEW2_AVAILABLE)
  target_include_directories(nekoplayer_lyrics_view PRIVATE "${NEKO_WEBVIEW2_INCLUDE_DIR}")
  target_link_libraries(nekoplayer_lyrics_view PRIVATE "${NEKO_WEBVIEW2_LIBRARY}" version oleaut32 advapi32)
else()
  target_compile_definitions(nekoplayer_lyrics_view PRIVATE NEKO_NO_WEBVIEW2)
endif()
target_link_libraries(${BINARY_NAME} PRIVATE nekoplayer_lyrics_view)
# Native crash reporting (minidump + report) lives in its own library because
# it uses C++ exceptions, which the runner target disables.
add_library(nekoplayer_crash_handler STATIC "crash_handler.cpp")
target_compile_features(nekoplayer_crash_handler PRIVATE cxx_std_20)
target_compile_definitions(nekoplayer_crash_handler PRIVATE NOMINMAX _HAS_EXCEPTIONS=1)
target_compile_options(nekoplayer_crash_handler PRIVATE /EHsc /utf-8)
target_link_libraries(nekoplayer_crash_handler PRIVATE shell32 ole32 user32)
target_link_libraries(${BINARY_NAME} PRIVATE nekoplayer_crash_handler)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
