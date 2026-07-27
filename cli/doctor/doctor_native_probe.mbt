///|
let doctor_native_expected_abi_version : Int = 1

///|
let doctor_native_ok : Int = 0

///|
let doctor_native_load_error : Int = -1

///|
let doctor_native_symbol_error : Int = -2

///|
let doctor_native_invalid_handle : Int = -5

///|
let doctor_native_abi_mismatch : Int = -6

///|
let doctor_native_buffer_too_small : Int = -11

///|
let doctor_native_max_text_length : Int = 1024 * 1024

///|
priv enum DoctorNativeProbeError {
  LoadFailed(String)
  SymbolsMissing(String)
  AbiMismatch(Int)
  OpenFailed(Int, String)
}

///|
priv struct DoctorNativeCallError {
  status : Int
  message : String
}

///|
priv enum DoctorNativeSmokeResult {
  Skipped
  Succeeded
  CreateFailed(DoctorNativeCallError)
  DestroyFailed(DoctorNativeCallError)
}

///|
priv struct DoctorNativeProbeResult {
  info : Result[String, DoctorNativeCallError]
  probe : Result[Unit, DoctorNativeCallError]
  smoke : DoctorNativeSmokeResult
}

///|
priv type DoctorNativeLibrary

///|
#borrow(library_path, out_abi_version, out_status, error_buffer)
extern "C" fn proton_doctor_native_open_ffi(
  library_path : Bytes,
  expected_abi_version : Int,
  out_abi_version : Ref[Int],
  out_status : Ref[Int],
  error_buffer : FixedArray[Byte],
  error_buffer_len : Int,
) -> DoctorNativeLibrary = "proton_doctor_native_open"

///|
#borrow(handle)
extern "C" fn proton_doctor_native_close_ffi(
  handle : DoctorNativeLibrary,
) -> Int = "proton_doctor_native_close"

///|
#borrow(handle)
extern "C" fn proton_doctor_native_abandon_ffi(
  handle : DoctorNativeLibrary,
) -> Int = "proton_doctor_native_abandon"

///|
#borrow(handle, buffer, out_required_len)
extern "C" fn proton_doctor_native_runtime_info_json_ffi(
  handle : DoctorNativeLibrary,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_doctor_native_runtime_info_json"

///|
#borrow(handle, config_json)
extern "C" fn proton_doctor_native_runtime_probe_json_ffi(
  handle : DoctorNativeLibrary,
  config_json : Bytes,
) -> Int = "proton_doctor_native_runtime_probe_json"

///|
#borrow(handle, buffer)
extern "C" fn proton_doctor_native_last_error_message_ffi(
  handle : DoctorNativeLibrary,
  buffer : FixedArray[Byte],
  buffer_len : Int,
) -> Int = "proton_doctor_native_last_error_message"

///|
#borrow(handle, config_json, out_runtime)
extern "C" fn proton_doctor_native_runtime_create_json_ffi(
  handle : DoctorNativeLibrary,
  config_json : Bytes,
  out_runtime : Ref[Int64],
) -> Int = "proton_doctor_native_runtime_create_json"

///|
#borrow(handle)
extern "C" fn proton_doctor_native_runtime_destroy_ffi(
  handle : DoctorNativeLibrary,
  runtime : Int64,
) -> Int = "proton_doctor_native_runtime_destroy"

///|
fn doctor_native_checked_buffer_length(required : Int) -> Int? {
  if required < 0 || required > doctor_native_max_text_length {
    None
  } else {
    Some(required + 1)
  }
}

///|
fn doctor_native_buffer_text(buffer : FixedArray[Byte]) -> String? {
  let bytes = Bytes::from_array(buffer)
  let end = match bytes.find(b"\x00") {
    Some(index) => index
    None => return None
  }
  Some(@ffi.from_cstr(bytes[0:end + 1].to_owned()))
}

///|
fn doctor_native_buffer_text_at_length(
  buffer : FixedArray[Byte],
  required : Int,
) -> String? {
  if required < 0 || required >= buffer.length() {
    return None
  }
  let bytes = Bytes::from_array(buffer)
  match bytes.find(b"\x00") {
    Some(index) if index == required =>
      Some(@ffi.from_cstr(bytes[0:index + 1].to_owned()))
    _ => None
  }
}

///|
fn doctor_native_open_with_expected_abi(
  library_path : String,
  expected_abi_version : Int,
) -> Result[DoctorNativeLibrary, DoctorNativeProbeError] {
  let actual_abi_version = Ref(0)
  let status = Ref(doctor_native_invalid_handle)
  let error_buffer = FixedArray::make(4096, b'\x00')
  let handle = proton_doctor_native_open_ffi(
    @ffi.to_cstr(library_path),
    expected_abi_version,
    actual_abi_version,
    status,
    error_buffer,
    error_buffer.length(),
  )
  let message = doctor_native_buffer_text(error_buffer).unwrap_or(
    "native probe bridge returned unterminated error text",
  )
  if status.val == doctor_native_load_error {
    return Err(LoadFailed(message))
  }
  if status.val == doctor_native_symbol_error {
    return Err(SymbolsMissing(message))
  }
  if status.val == doctor_native_abi_mismatch {
    return Err(AbiMismatch(actual_abi_version.val))
  }
  if status.val == doctor_native_ok {
    return Ok(handle)
  }
  Err(OpenFailed(status.val, message))
}

///|
fn doctor_native_open(
  library_path : String,
) -> Result[DoctorNativeLibrary, DoctorNativeProbeError] {
  doctor_native_open_with_expected_abi(
    library_path, doctor_native_expected_abi_version,
  )
}

///|
fn DoctorNativeCallError::hint(
  self : DoctorNativeCallError,
  fallback : String,
) -> String {
  if self.message == "" {
    fallback + " with status " + self.status.to_string()
  } else {
    self.message
  }
}

///|
fn doctor_native_read_info(
  handle : DoctorNativeLibrary,
) -> Result[String, DoctorNativeCallError] {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_doctor_native_runtime_info_json_ffi(
    handle, scratch, 0, required,
  )
  if status < 0 && status != doctor_native_buffer_too_small {
    return Err({ status, message: doctor_native_last_error(handle) })
  }
  if required.val < 0 {
    return Err({
      status,
      message: "runtime info ABI returned a negative required length",
    })
  }
  let buffer_length = match doctor_native_checked_buffer_length(required.val) {
    Some(length) => length
    None =>
      return Err({
        status,
        message: "runtime info ABI required length exceeds the safety limit",
      })
  }
  let first_required = required.val
  let buffer = FixedArray::make(buffer_length, b'\x00')
  let second_status = proton_doctor_native_runtime_info_json_ffi(
    handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    Err({ status: second_status, message: doctor_native_last_error(handle) })
  } else if required.val < 0 {
    Err({
      status: second_status,
      message: "runtime info ABI returned a negative required length",
    })
  } else if required.val > first_required {
    Err({
      status: second_status,
      message: "runtime info ABI required length grew while reading",
    })
  } else {
    match doctor_native_buffer_text_at_length(buffer, required.val) {
      Some(text) => Ok(text)
      None =>
        Err({
          status: second_status,
          message: "runtime info ABI returned text with an inconsistent length",
        })
    }
  }
}

///|
fn doctor_native_last_error(handle : DoctorNativeLibrary) -> String {
  let scratch = FixedArray::make(1, b'\x00')
  let required = proton_doctor_native_last_error_message_ffi(handle, scratch, 0)
  if required < 0 {
    return "native error message ABI failed with status " + required.to_string()
  }
  if required == 0 {
    return ""
  }
  let buffer_length = match doctor_native_checked_buffer_length(required) {
    Some(length) => length
    None => return "native error message exceeds the safety limit"
  }
  let buffer = FixedArray::make(buffer_length, b'\x00')
  let second_required = proton_doctor_native_last_error_message_ffi(
    handle,
    buffer,
    buffer.length(),
  )
  if second_required < 0 {
    return "native error message ABI failed with status " +
      second_required.to_string()
  }
  if second_required > required {
    return "native error message required length grew while reading"
  }
  doctor_native_buffer_text_at_length(buffer, second_required).unwrap_or(
    "native error message ABI returned text with an inconsistent length",
  )
}

///|
fn doctor_native_smoke(
  handle : DoctorNativeLibrary,
  config : Bytes,
) -> DoctorNativeSmokeResult {
  let runtime = Ref(0L)
  let create_status = proton_doctor_native_runtime_create_json_ffi(
    handle, config, runtime,
  )
  if create_status < 0 {
    return CreateFailed({
      status: create_status,
      message: doctor_native_last_error(handle),
    })
  }
  let destroy_status = proton_doctor_native_runtime_destroy_ffi(
    handle,
    runtime.val,
  )
  if destroy_status < 0 {
    let error = DoctorNativeCallError::{
      status: destroy_status,
      message: doctor_native_last_error(handle),
    }
    let _ = proton_doctor_native_abandon_ffi(handle)
    DestroyFailed(error)
  } else {
    Succeeded
  }
}

///|
fn doctor_native_probe(
  library_path : String,
  config_json : String,
) -> Result[DoctorNativeProbeResult, DoctorNativeProbeError] {
  let handle = match doctor_native_open(library_path) {
    Ok(handle) => handle
    Err(error) => return Err(error)
  }
  defer {
    let _ = proton_doctor_native_close_ffi(handle)
  }
  let info = doctor_native_read_info(handle)
  let config = @ffi.to_cstr(config_json)
  let probe_status = proton_doctor_native_runtime_probe_json_ffi(handle, config)
  let probe = if probe_status < 0 {
    Err({ status: probe_status, message: doctor_native_last_error(handle) })
  } else {
    Ok(())
  }
  let smoke = if probe_status < 0 {
    Skipped
  } else {
    doctor_native_smoke(handle, config)
  }
  Ok({ info, probe, smoke })
}
