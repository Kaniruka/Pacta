cmake_minimum_required(VERSION 3.23)
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
  "windows_notification_bridge.cpp"
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
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# Windows App SDK notifications: C++/WinRT projections and the WinRT ABI.
target_link_libraries(${BINARY_NAME} PRIVATE "runtimeobject.lib" "WindowsApp.lib")

# Windows App SDK packages used by the notification bridge. Restored below,
# before MSBuild evaluates the generated project for the first time.
set(PACTA_WINDOWSAPPSDK_VERSION "2.6.5")
set(PACTA_CPPWINRT_VERSION "3.0.260818.1")

# The runner registers its own Windows App SDK notification identity and keeps
# the scheduled queue in the OS. The packages copy the self-contained runtime
# beside the executable, so no runtime installer, MSIX registration or identity
# change is required.
set_target_properties(${BINARY_NAME} PROPERTIES
  VS_PACKAGE_REFERENCES "Microsoft.WindowsAppSDK.Base_${PACTA_WINDOWSAPPSDK_VERSION};Microsoft.WindowsAppSDK.Foundation_${PACTA_WINDOWSAPPSDK_VERSION};Microsoft.Windows.CppWinRT_${PACTA_CPPWINRT_VERSION}"
  VS_GLOBAL_RestoreProjectStyle "PackageReference"
  VS_GLOBAL_WindowsAppSDKSelfContained "true"
  VS_GLOBAL_AppxPackage "false"
  VS_GLOBAL_EnableMsixTooling "false"
  # CppWinRTEnabled is deliberately left unset: the NuGet package then supplies
  # its own cppwinrt.exe, while forcing the property would point the projection
  # step at a build-time path this project does not have.
  VS_GLOBAL_GenerateProjectPriFile "false"
)
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "advapi32.lib")
# COM file picker for the account avatar (IFileOpenDialog).
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib" "uuid.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# --- Windows App SDK package restore ----------------------------------------
#
# The notification bridge compiles against the Windows App SDK's C++/WinRT
# projections. CMake generates the PackageReference items, but this generator
# does not emit the automatic NuGet Restore step, so the runner restores them
# during generation. Restore writes <runner>/obj/pacta.vcxproj.nuget.g.props,
# which the generated project imports before it compiles anything; without it
# the projection headers do not exist.
set(PACTA_OBJ_DIR "${CMAKE_CURRENT_BINARY_DIR}/obj/")
set(PACTA_RESTORE_DIR "${CMAKE_CURRENT_BINARY_DIR}/nuget-restore")
set(PACTA_WINDOWS_SDK_VERSION "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
if(PACTA_WINDOWS_SDK_VERSION STREQUAL "")
  set(PACTA_WINDOWS_SDK_VERSION "10.0.26100.0")
endif()
set(PACTA_PLATFORM_TOOLSET "${CMAKE_VS_PLATFORM_TOOLSET}")
if(PACTA_PLATFORM_TOOLSET STREQUAL "")
  set(PACTA_PLATFORM_TOOLSET "v145")
endif()

if(MSVC AND CMAKE_VS_MSBUILD_COMMAND)
  file(MAKE_DIRECTORY "${PACTA_OBJ_DIR}" "${PACTA_RESTORE_DIR}")
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/nuget_restore.vcxproj.in"
    "${PACTA_RESTORE_DIR}/pacta.vcxproj"
    @ONLY)
  execute_process(
    COMMAND "${CMAKE_VS_MSBUILD_COMMAND}"
            "${PACTA_RESTORE_DIR}/pacta.vcxproj"
            -t:Restore
            -p:Configuration=Release
            -p:Platform=x64
            -nologo
            -v:minimal
    RESULT_VARIABLE PACTA_RESTORE_RESULT
    OUTPUT_VARIABLE PACTA_RESTORE_OUTPUT
    ERROR_VARIABLE PACTA_RESTORE_OUTPUT)
  if(NOT PACTA_RESTORE_RESULT EQUAL 0)
    message(FATAL_ERROR
      "Restoring the Windows App SDK packages failed:\n${PACTA_RESTORE_OUTPUT}")
  endif()
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
