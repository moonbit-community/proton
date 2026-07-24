cmake_minimum_required(VERSION 3.20)

project(proton_native C)

include(CTest)

if(NOT WIN32)
  find_package(Threads REQUIRED)
endif()

option(PROTON_WITH_ENGINE "Build Proton with the native browser engine linked" OFF)
set(PROTON_ENGINE_ROOT "" CACHE PATH "Native browser engine runtime/SDK root")
set(PROTON_ENGINE_SOURCES src/engine/proton_engine_none.c)
set(PROTON_APP_RUNNER_SOURCE src/app_runner_stub.c)
set(PROTON_NOTIFICATION_SOURCE src/engine/notification_stub.c)

if(PROTON_WITH_ENGINE)
  if(WIN32)
    set(PROTON_APP_RUNNER_SOURCE src/app_runner_win.c)
    set(PROTON_ENGINE_SOURCES
      src/engine/cef_win/proton_engine_cef_win.c
      src/engine/cef_win/proton_win_titlebar.c
    )
  elseif(APPLE)
    enable_language(OBJC CXX OBJCXX)
    set(PROTON_APP_RUNNER_SOURCE src/app_runner.m)
    set(PROTON_NOTIFICATION_SOURCE src/engine/cef_mac/notification.m)
    set(PROTON_ENGINE_SOURCES
      src/engine/cef_mac/proton_engine_cef_mac.m
      src/engine/cef_mac/dialog.m
      src/engine/cef_mac/menu.m
      src/engine/cef_mac/scheme.m
    )
  elseif(UNIX)
    set(PROTON_ENGINE_SOURCES
      src/engine/cef_linux/proton_engine_cef_linux.c
      src/engine/cef_linux/proton_linux_titlebar.c
    )
  else()
    message(FATAL_ERROR "PROTON_WITH_ENGINE is not wired for this platform")
  endif()
  list(APPEND PROTON_ENGINE_SOURCES
    src/engine/cef_common/bridge_policy.c
    src/engine/cef_common/bridge_renderer.c
  )
endif()

if(PROTON_WITH_ENGINE AND UNIX AND NOT APPLE)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(PROTON_GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
  pkg_check_modules(PROTON_X11 REQUIRED IMPORTED_TARGET x11)
endif()

add_library(proton SHARED
  src/proton_config.c
  src/proton_json.c
  src/proton_state.c
  src/proton.c
  ${PROTON_APP_RUNNER_SOURCE}
  ${PROTON_NOTIFICATION_SOURCE}
  src/engine/cef_common/bridge_lifecycle.c
  ${PROTON_ENGINE_SOURCES}
)

target_include_directories(proton
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(proton
  PRIVATE
    PROTON_BUILD
)

if(NOT WIN32)
  target_link_libraries(proton PRIVATE Threads::Threads)
endif()
if(UNIX AND NOT APPLE)
  target_link_libraries(proton PRIVATE ${CMAKE_DL_LIBS})
endif()

if(PROTON_WITH_ENGINE)
  if(PROTON_ENGINE_ROOT STREQUAL "")
    message(FATAL_ERROR "PROTON_WITH_ENGINE=ON requires PROTON_ENGINE_ROOT")
  endif()

  target_compile_definitions(proton PRIVATE PROTON_WITH_ENGINE=1)
  target_compile_definitions(proton PRIVATE CEF_API_VERSION=14700)
  target_include_directories(proton PRIVATE "${PROTON_ENGINE_ROOT}")
  if(UNIX AND NOT APPLE)
    target_compile_definitions(proton PRIVATE OS_LINUX=1 CEF_X11=1)
  endif()
  if(APPLE)
    set(PROTON_ENGINE_FRAMEWORK_PARENT "${PROTON_ENGINE_ROOT}/Release")
    set(PROTON_ENGINE_FRAMEWORK_DIR "${PROTON_ENGINE_FRAMEWORK_PARENT}/Chromium Embedded Framework.framework")
    set(PROTON_ENGINE_FRAMEWORK_BINARY "${PROTON_ENGINE_FRAMEWORK_DIR}/Chromium Embedded Framework")
    set(PROTON_ENGINE_RESOURCES_DIR "${PROTON_ENGINE_FRAMEWORK_DIR}/Resources")
    target_compile_options(proton PRIVATE $<$<COMPILE_LANGUAGE:OBJC>:-fblocks>)
  else()
    set(PROTON_ENGINE_RESOURCES_DIR "${PROTON_ENGINE_ROOT}/Resources")
  endif()
  set(PROTON_ENGINE_LOCALES_DIR "${PROTON_ENGINE_RESOURCES_DIR}/locales")
  set(PROTON_ENGINE_ICU_DATA "${PROTON_ENGINE_RESOURCES_DIR}/icudtl.dat")

  if(WIN32)
    set(PROTON_ENGINE_IMPORT_LIB "${PROTON_ENGINE_ROOT}/Release/libcef.lib")
    set(PROTON_ENGINE_RUNTIME_DLL "${PROTON_ENGINE_ROOT}/Release/libcef.dll")
    if(NOT EXISTS "${PROTON_ENGINE_IMPORT_LIB}")
      message(FATAL_ERROR "Missing engine import library: ${PROTON_ENGINE_IMPORT_LIB}")
    endif()
    if(NOT EXISTS "${PROTON_ENGINE_RUNTIME_DLL}")
      message(FATAL_ERROR "Missing engine runtime library: ${PROTON_ENGINE_RUNTIME_DLL}")
    endif()
    if(NOT EXISTS "${PROTON_ENGINE_ICU_DATA}")
      message(FATAL_ERROR "Missing engine ICU data: ${PROTON_ENGINE_ICU_DATA}")
    endif()
    if(NOT IS_DIRECTORY "${PROTON_ENGINE_LOCALES_DIR}")
      message(FATAL_ERROR "Missing engine locales directory: ${PROTON_ENGINE_LOCALES_DIR}")
    endif()
    file(GLOB PROTON_ENGINE_RUNTIME_DLLS "${PROTON_ENGINE_ROOT}/Release/*.dll")
    file(GLOB PROTON_ENGINE_RUNTIME_DATA
      "${PROTON_ENGINE_ROOT}/Release/*.bin"
      "${PROTON_ENGINE_ROOT}/Release/*.dat"
      "${PROTON_ENGINE_ROOT}/Release/*.json"
      "${PROTON_ENGINE_ROOT}/Release/*.pak"
    )
    target_link_libraries(proton PRIVATE "${PROTON_ENGINE_IMPORT_LIB}")
    add_executable(cef_process
      src/cef_process.c
    )
    target_link_libraries(cef_process PRIVATE proton)
    target_include_directories(cef_process
      PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
    set_target_properties(cef_process PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    )
    install(FILES ${PROTON_ENGINE_RUNTIME_DLLS} DESTINATION bin)
    install(FILES ${PROTON_ENGINE_RUNTIME_DATA} DESTINATION bin)
    install(DIRECTORY "${PROTON_ENGINE_RESOURCES_DIR}/" DESTINATION Resources)
    install(TARGETS cef_process RUNTIME DESTINATION bin)
  elseif(APPLE)
    if(NOT EXISTS "${PROTON_ENGINE_FRAMEWORK_BINARY}")
      message(FATAL_ERROR "Missing engine framework binary: ${PROTON_ENGINE_FRAMEWORK_BINARY}")
    endif()
    if(NOT EXISTS "${PROTON_ENGINE_ICU_DATA}")
      message(FATAL_ERROR "Missing engine ICU data: ${PROTON_ENGINE_ICU_DATA}")
    endif()
    add_library(proton_cef_loader STATIC
      "${PROTON_ENGINE_ROOT}/libcef_dll/wrapper/libcef_dll_dylib.cc"
      "${PROTON_ENGINE_ROOT}/libcef_dll/wrapper/cef_scoped_library_loader_mac.mm"
    )
    target_include_directories(proton_cef_loader PRIVATE "${PROTON_ENGINE_ROOT}")
    target_compile_definitions(proton_cef_loader PRIVATE WRAPPING_CEF_SHARED=1)
    target_compile_features(proton_cef_loader PRIVATE cxx_std_17)
    target_link_libraries(proton PRIVATE
      proton_cef_loader
      "-framework Cocoa"
      "-framework AppKit"
      "-framework Foundation"
      "-framework UserNotifications"
      "-lc++"
    )
    set_target_properties(proton PROPERTIES LINKER_LANGUAGE CXX)
    set_target_properties(proton PROPERTIES
      INSTALL_RPATH "@loader_path/../Frameworks;@loader_path"
      BUILD_WITH_INSTALL_RPATH ON
    )
    add_custom_command(TARGET proton POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E make_directory
              "$<TARGET_FILE_DIR:proton>/../Frameworks"
      COMMAND "${CMAKE_COMMAND}" -E copy_directory
              "${PROTON_ENGINE_FRAMEWORK_DIR}"
              "$<TARGET_FILE_DIR:proton>/../Frameworks/Chromium Embedded Framework.framework"
      COMMAND "${CMAKE_COMMAND}" -E copy_directory
              "${PROTON_ENGINE_RESOURCES_DIR}"
              "$<TARGET_FILE_DIR:proton>/../Resources"
      VERBATIM
    )
    add_executable(cef_process
      src/cef_process.c
    )
    target_link_libraries(cef_process PRIVATE proton)
    target_include_directories(cef_process
      PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
    set_target_properties(cef_process PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
      INSTALL_RPATH "@loader_path/../lib;@loader_path/../Frameworks"
      BUILD_WITH_INSTALL_RPATH ON
    )
    install(DIRECTORY "${PROTON_ENGINE_FRAMEWORK_DIR}" DESTINATION Frameworks)
    install(DIRECTORY "${PROTON_ENGINE_RESOURCES_DIR}/" DESTINATION Resources)
    install(FILES
      "${PROTON_ENGINE_FRAMEWORK_DIR}/Libraries/libEGL.dylib"
      "${PROTON_ENGINE_FRAMEWORK_DIR}/Libraries/libGLESv2.dylib"
      "${PROTON_ENGINE_FRAMEWORK_DIR}/Libraries/libvk_swiftshader.dylib"
      DESTINATION bin
    )
    install(TARGETS cef_process RUNTIME DESTINATION bin)
  elseif(UNIX)
    set(PROTON_ENGINE_SHARED_LIB "${PROTON_ENGINE_ROOT}/Release/libcef.so")
    if(NOT EXISTS "${PROTON_ENGINE_SHARED_LIB}")
      message(FATAL_ERROR "Missing engine shared library: ${PROTON_ENGINE_SHARED_LIB}")
    endif()
    if(NOT EXISTS "${PROTON_ENGINE_ICU_DATA}")
      message(FATAL_ERROR "Missing engine ICU data: ${PROTON_ENGINE_ICU_DATA}")
    endif()
    if(NOT IS_DIRECTORY "${PROTON_ENGINE_LOCALES_DIR}")
      message(FATAL_ERROR "Missing engine locales directory: ${PROTON_ENGINE_LOCALES_DIR}")
    endif()
    target_link_libraries(proton PRIVATE
      "${PROTON_ENGINE_SHARED_LIB}"
      PkgConfig::PROTON_GTK3
      PkgConfig::PROTON_X11
      ${CMAKE_DL_LIBS}
    )
    target_link_options(proton INTERFACE
      "LINKER:-rpath-link,${PROTON_ENGINE_ROOT}/Release"
    )
    set_target_properties(proton PROPERTIES
      INSTALL_RPATH "$ORIGIN;$ORIGIN/../bin"
      BUILD_WITH_INSTALL_RPATH ON
      BUILD_RPATH "${PROTON_ENGINE_ROOT}/Release"
    )
    add_executable(cef_process
      src/cef_process.c
    )
    target_link_libraries(cef_process PRIVATE
      proton
      "${PROTON_ENGINE_SHARED_LIB}"
    )
    target_include_directories(cef_process
      PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
    target_link_options(cef_process PRIVATE
      "LINKER:--no-as-needed"
    )
    set_target_properties(cef_process PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
      INSTALL_RPATH "$ORIGIN/../lib;$ORIGIN"
      BUILD_WITH_INSTALL_RPATH ON
      BUILD_RPATH "${PROTON_ENGINE_ROOT}/Release"
    )
    file(GLOB PROTON_ENGINE_RUNTIME_LIBS
      "${PROTON_ENGINE_ROOT}/Release/*.so"
      "${PROTON_ENGINE_ROOT}/Release/*.so.*"
    )
    file(GLOB PROTON_ENGINE_RUNTIME_DATA
      "${PROTON_ENGINE_ROOT}/Release/*.bin"
      "${PROTON_ENGINE_ROOT}/Release/*.dat"
      "${PROTON_ENGINE_ROOT}/Release/*.json"
      "${PROTON_ENGINE_ROOT}/Release/*.pak"
    )
    file(GLOB PROTON_ENGINE_RESOURCE_PAKS
      "${PROTON_ENGINE_RESOURCES_DIR}/*.pak"
    )
    install(FILES ${PROTON_ENGINE_RUNTIME_LIBS} DESTINATION bin)
    install(FILES ${PROTON_ENGINE_RUNTIME_DATA} DESTINATION bin)
    install(FILES "${PROTON_ENGINE_ICU_DATA}" ${PROTON_ENGINE_RESOURCE_PAKS}
            DESTINATION bin)
    if(EXISTS "${PROTON_ENGINE_ROOT}/Release/chrome-sandbox")
      install(PROGRAMS "${PROTON_ENGINE_ROOT}/Release/chrome-sandbox"
              DESTINATION bin)
    endif()
    install(DIRECTORY "${PROTON_ENGINE_RESOURCES_DIR}/" DESTINATION Resources)
    install(TARGETS cef_process RUNTIME DESTINATION bin)

    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../proton/moon.mod"
         PROTON_MOON_VERSION_LINE REGEX "^version = ")
    string(REGEX REPLACE "^version = \"([^\"]+)\".*$" "\\1"
           PROTON_PREBUILT_VERSION "${PROTON_MOON_VERSION_LINE}")
    set(PROTON_PREBUILT_MANIFEST "${CMAKE_BINARY_DIR}/proton_prebuilt_manifest.json")
    file(WRITE "${PROTON_PREBUILT_MANIFEST}"
      "{\n"
      "  \"platform\": \"linux-x64\",\n"
      "  \"proton_version\": \"${PROTON_PREBUILT_VERSION}\",\n"
      "  \"artifacts\": {\n"
      "    \"shared_lib\": \"lib/libproton.so\",\n"
      "    \"helper\": \"bin/cef_process\",\n"
      "    \"header\": \"include/proton_native.h\"\n"
      "  }\n"
      "}\n"
    )
    install(FILES "${PROTON_PREBUILT_MANIFEST}" DESTINATION .
            RENAME manifest.json)
  endif()
else()
  target_compile_definitions(proton PRIVATE PROTON_WITH_ENGINE=0)
endif()

set_target_properties(proton PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  OBJC_VISIBILITY_PRESET hidden
  OBJCXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

if(WIN32)
  target_compile_definitions(proton PRIVATE
    _WIN32_WINNT=0x0A00
    WINVER=0x0A00
  )
  target_link_libraries(proton PRIVATE comctl32 dwmapi)
  set_target_properties(proton PROPERTIES PREFIX "")
endif()

install(TARGETS proton
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)

install(FILES include/proton_native.h DESTINATION include)

if(BUILD_TESTING)
  add_executable(proton_smoke
    tests/proton_smoke.c
    src/engine/cef_common/bridge_lifecycle.c
    src/proton_json.c
  )
  add_executable(proton_exports_smoke
    tests/proton_exports_smoke.c
  )

  target_link_libraries(proton_smoke PRIVATE proton)
  if(NOT WIN32)
    target_link_libraries(proton_exports_smoke PRIVATE ${CMAKE_DL_LIBS})
  endif()

  add_test(NAME proton_smoke COMMAND proton_smoke)
  add_test(NAME proton_exports_smoke COMMAND proton_exports_smoke)
  set_tests_properties(proton_smoke PROPERTIES TIMEOUT 90)

  if(WIN32)
    set(PROTON_TEST_PATH_MODIFICATIONS
      "PATH=path_list_prepend:$<TARGET_FILE_DIR:proton>"
    )
    if(PROTON_WITH_ENGINE)
      list(APPEND PROTON_TEST_PATH_MODIFICATIONS
        "PATH=path_list_prepend:${PROTON_ENGINE_ROOT}/Release"
      )
    endif()
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.22")
      set_tests_properties(proton_smoke PROPERTIES
        ENVIRONMENT_MODIFICATION "${PROTON_TEST_PATH_MODIFICATIONS}"
      )
      set_tests_properties(proton_exports_smoke PROPERTIES
        ENVIRONMENT_MODIFICATION "${PROTON_TEST_PATH_MODIFICATIONS}"
      )
    else()
      if(PROTON_WITH_ENGINE)
        set(PROTON_TEST_PATH "$<TARGET_FILE_DIR:proton>;${PROTON_ENGINE_ROOT}/Release;$ENV{PATH}")
      else()
        set(PROTON_TEST_PATH "$<TARGET_FILE_DIR:proton>;$ENV{PATH}")
      endif()
      set_tests_properties(proton_smoke PROPERTIES
        ENVIRONMENT "PATH=${PROTON_TEST_PATH}"
      )
      set_tests_properties(proton_exports_smoke PROPERTIES
        ENVIRONMENT "PATH=${PROTON_TEST_PATH}"
      )
    endif()
    if(PROTON_WITH_ENGINE)
      set_tests_properties(proton_smoke PROPERTIES
        ENVIRONMENT
          "PROTON_TEST_RUNTIME_ROOT=${CMAKE_INSTALL_PREFIX};PROTON_TEST_HELPER_PATH=$<TARGET_FILE:cef_process>;PROTON_NATIVE_LOG=${CMAKE_BINARY_DIR}/proton-smoke-native.log;PROTON_TEST_NATIVE_LOG=${CMAKE_BINARY_DIR}/proton-smoke-native.log"
      )
    endif()
  elseif(APPLE)
    if(PROTON_WITH_ENGINE)
      set_tests_properties(proton_smoke PROPERTIES
        ENVIRONMENT
          "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{DYLD_LIBRARY_PATH};PROTON_TEST_RUNTIME_ROOT=${CMAKE_BINARY_DIR};PROTON_TEST_HELPER_PATH=$<TARGET_FILE:cef_process>;PROTON_NATIVE_LOG=${CMAKE_BINARY_DIR}/proton-smoke-native.log;PROTON_TEST_NATIVE_LOG=${CMAKE_BINARY_DIR}/proton-smoke-native.log"
      )
    else()
      set_tests_properties(proton_smoke PROPERTIES
        ENVIRONMENT
          "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{DYLD_LIBRARY_PATH}"
      )
    endif()
    set_tests_properties(proton_exports_smoke PROPERTIES
      ENVIRONMENT "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{DYLD_LIBRARY_PATH}"
    )
  else()
    if(PROTON_WITH_ENGINE)
      set(PROTON_TEST_LD_LIBRARY_PATH
        "$<TARGET_FILE_DIR:proton>:${PROTON_ENGINE_ROOT}/Release:$ENV{LD_LIBRARY_PATH}"
      )
    else()
      set(PROTON_TEST_LD_LIBRARY_PATH
        "$<TARGET_FILE_DIR:proton>:$ENV{LD_LIBRARY_PATH}"
      )
    endif()
    set_tests_properties(proton_smoke PROPERTIES
      ENVIRONMENT "LD_LIBRARY_PATH=${PROTON_TEST_LD_LIBRARY_PATH}"
    )
    set_tests_properties(proton_exports_smoke PROPERTIES
      ENVIRONMENT "LD_LIBRARY_PATH=${PROTON_TEST_LD_LIBRARY_PATH}"
    )
  endif()
endif()
