///|
extern "C" fn download_deny_after_update_trace_ffi() -> Bytes = "proton_test_download_deny_after_update_trace"

///|
extern "C" fn download_deny_before_update_trace_ffi() -> Bytes = "proton_test_download_deny_before_update_trace"

///|
extern "C" fn download_invalid_response_trace_ffi() -> Bytes = "proton_test_download_invalid_response_trace"

///|
extern "C" fn download_empty_response_trace_ffi() -> Bytes = "proton_test_download_empty_response_trace"

///|
extern "C" fn denied_download_policy_trace_ffi() -> Bytes = "proton_test_denied_download_policy_trace"

///|
extern "C" fn unpublished_download_request_trace_ffi() -> Bytes = "proton_test_unpublished_download_request_trace"

///|
extern "C" fn download_single_completion_trace_ffi() -> Bytes = "proton_test_download_single_completion_trace"

///|
extern "C" fn download_command_beats_allow_trace_ffi() -> Bytes = "proton_test_download_command_beats_allow_trace"

///|
pub fn download_deny_after_update_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_deny_after_update_trace_ffi())
}

///|
pub fn download_deny_before_update_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_deny_before_update_trace_ffi())
}

///|
pub fn download_invalid_response_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_invalid_response_trace_ffi())
}

///|
pub fn download_empty_response_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_empty_response_trace_ffi())
}

///|
pub fn denied_download_policy_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(denied_download_policy_trace_ffi())
}

///|
pub fn unpublished_download_request_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(unpublished_download_request_trace_ffi())
}

///|
pub fn download_single_completion_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_single_completion_trace_ffi())
}

///|
pub fn download_command_beats_allow_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(download_command_beats_allow_trace_ffi())
}
