if(NOT DEFINED PROTON_SMOKE_EXECUTABLE OR
   PROTON_SMOKE_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "PROTON_SMOKE_EXECUTABLE is required")
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
  message(FATAL_ERROR
    "proton_smoke failed: ${result}\n"
    "--- Proton native log ---\n"
    "${native_log}\n"
    "--- End Proton native log ---"
  )
endif()
