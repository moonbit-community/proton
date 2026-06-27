cmake_minimum_required(VERSION 3.20)

project(proton_native C)

include(CTest)

if(NOT WIN32)
  find_package(Threads REQUIRED)
endif()

option(PROTON_WITH_ENGINE "Build Proton with the native browser engine linked" OFF)
set(PROTON_ENGINE_ROOT "" CACHE PATH "Native browser engine runtime/SDK root")
set(PROTON_ENGINE_SOURCE src/engine/proton_engine_none.c)

if(PROTON_WITH_ENGINE)
  if(WIN32)
    set(PROTON_ENGINE_SOURCE src/engine/cef_win/proton_engine_cef_win.c)
  elseif(APPLE)
    enable_language(OBJC)
    set(PROTON_ENGINE_SOURCE src/engine/cef_mac/proton_engine_cef_mac.m)
  else()
    message(FATAL_ERROR "PROTON_WITH_ENGINE is not wired for this platform")
  endif()
endif()

add_library(proton SHARED
  src/proton_json.c
  src/proton.c
  ${PROTON_ENGINE_SOURCE}
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

if(PROTON_WITH_ENGINE)
  if(PROTON_ENGINE_ROOT STREQUAL "")
    message(FATAL_ERROR "PROTON_WITH_ENGINE=ON requires PROTON_ENGINE_ROOT")
  endif()

  target_compile_definitions(proton PRIVATE PROTON_WITH_ENGINE=1)
  target_compile_definitions(proton PRIVATE CEF_API_VERSION=14700)
  target_include_directories(proton PRIVATE "${PROTON_ENGINE_ROOT}")
  if(APPLE)
    set(PROTON_ENGINE_FRAMEWORK_PARENT "${PROTON_ENGINE_ROOT}/Release")
    set(PROTON_ENGINE_FRAMEWORK_DIR "${PROTON_ENGINE_FRAMEWORK_PARENT}/Chromium Embedded Framework.framework")
    set(PROTON_ENGINE_FRAMEWORK_BINARY "${PROTON_ENGINE_FRAMEWORK_DIR}/Chromium Embedded Framework")
    set(PROTON_ENGINE_RESOURCES_DIR "${PROTON_ENGINE_FRAMEWORK_DIR}/Resources")
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
    target_link_libraries(proton PRIVATE
      "${PROTON_ENGINE_FRAMEWORK_BINARY}"
      "-framework Cocoa"
      "-framework AppKit"
      "-framework Foundation"
    )
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
      COMMAND install_name_tool
              -change
              "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
              "@loader_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
              "$<TARGET_FILE:proton>"
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
  endif()
else()
  target_compile_definitions(proton PRIVATE PROTON_WITH_ENGINE=0)
endif()

set_target_properties(proton PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

install(TARGETS proton
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)

install(FILES include/proton_native.h DESTINATION include)

if(BUILD_TESTING)
  add_executable(proton_smoke
    tests/proton_smoke.c
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
  elseif(APPLE)
    set_tests_properties(proton_smoke PROPERTIES
      ENVIRONMENT "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{DYLD_LIBRARY_PATH}"
    )
    set_tests_properties(proton_exports_smoke PROPERTIES
      ENVIRONMENT "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{DYLD_LIBRARY_PATH}"
    )
  else()
    set_tests_properties(proton_smoke PROPERTIES
      ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{LD_LIBRARY_PATH}"
    )
    set_tests_properties(proton_exports_smoke PROPERTIES
      ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:proton>:$ENV{LD_LIBRARY_PATH}"
    )
  endif()
endif()
