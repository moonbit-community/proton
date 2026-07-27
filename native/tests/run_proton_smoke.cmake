if(NOT DEFINED PROTON_SMOKE_EXECUTABLE OR
   PROTON_SMOKE_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "PROTON_SMOKE_EXECUTABLE is required")
endif()

if(DEFINED PROTON_CEF_LOG_FILE AND NOT PROTON_CEF_LOG_FILE STREQUAL "")
  file(REMOVE "${PROTON_CEF_LOG_FILE}")
endif()

execute_process(
  COMMAND "${PROTON_SMOKE_EXECUTABLE}"
  RESULT_VARIABLE result
)

if(NOT "${result}" STREQUAL "0")
  set(native_log "")
  if(DEFINED ENV{PROTON_TEST_NATIVE_LOG} AND
     EXISTS "$ENV{PROTON_TEST_NATIVE_LOG}")
    file(READ "$ENV{PROTON_TEST_NATIVE_LOG}" native_log)
  endif()
  set(cef_log "")
  if(DEFINED PROTON_CEF_LOG_FILE AND
     EXISTS "${PROTON_CEF_LOG_FILE}")
    file(READ "${PROTON_CEF_LOG_FILE}" cef_log)
  endif()
  message(FATAL_ERROR
    "proton_smoke failed: ${result}\n"
    "--- Proton native log ---\n"
    "${native_log}\n"
    "--- End Proton native log ---\n"
    "--- CEF debug log ---\n"
    "${cef_log}\n"
    "--- End CEF debug log ---"
  )
endif()
