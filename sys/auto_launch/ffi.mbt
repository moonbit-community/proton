///|
/// Returns the native platform code for the current process.
extern "C" fn platform_code_ffi() -> Int = "mb_auto_launch_platform_code"

///|
/// Returns the current executable path as UTF-8 bytes, or an empty value.
extern "C" fn current_executable_path_ffi() -> Bytes = "mb_auto_launch_current_executable_path"

///|
/// Returns the current user's home directory as UTF-8 bytes, or an empty value.
extern "C" fn home_directory_ffi() -> Bytes = "mb_auto_launch_home_directory"

///|
/// Writes a UTF-8 text file and returns a native status code.
#borrow(path)
#owned(contents)
extern "C" fn write_text_file_ffi(path : Bytes, contents : Bytes) -> Int = "mb_auto_launch_write_text_file"

///|
/// Removes the file at `path` and returns a native status code.
#borrow(path)
extern "C" fn remove_file_ffi(path : Bytes) -> Int = "mb_auto_launch_remove_file"

///|
/// Checks whether the file at `path` exists.
#borrow(path)
extern "C" fn file_exists_ffi(path : Bytes) -> Int = "mb_auto_launch_file_exists"

///|
/// Creates or updates a current-user Windows `Run` registry value.
#borrow(name)
#owned(command)
extern "C" fn windows_set_run_entry_ffi(name : Bytes, command : Bytes) -> Int = "mb_auto_launch_windows_set_run_entry"

///|
/// Deletes a current-user Windows `Run` registry value.
#borrow(name)
extern "C" fn windows_delete_run_entry_ffi(name : Bytes) -> Int = "mb_auto_launch_windows_delete_run_entry"

///|
/// Queries whether a current-user Windows `Run` registry value exists.
#borrow(name)
extern "C" fn windows_run_entry_exists_ffi(name : Bytes) -> Int = "mb_auto_launch_windows_run_entry_exists"

///|
/// Returns the last native error code observed by the C shim.
extern "C" fn last_error_code_ffi() -> Int = "mb_auto_launch_last_error_code"

///|
/// Returns the last native error message as UTF-8 bytes.
extern "C" fn last_error_message_ffi() -> Bytes = "mb_auto_launch_last_error_message"

///|
/// Decodes UTF-8 bytes into a MoonBit string with lossy fallback.
fn decode_utf8(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes[:])
}

///|
/// Decodes optional text returned by the native layer.
fn decode_optional_text(bytes : Bytes) -> String? {
  let value = decode_utf8(bytes)
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// Decodes a native error message and falls back to `default_message`.
fn decode_error_message(bytes : Bytes, default_message : String) -> String {
  let message = decode_utf8(bytes)
  if message.is_empty() {
    default_message
  } else {
    message
  }
}

///|
/// Returns the last native error message or `default_message`.
fn last_error_message_or(default_message : String) -> String {
  decode_error_message(last_error_message_ffi(), default_message)
}

///|
/// Converts the last native failure into `AutoLaunchError`.
fn native_failure(
  action : String,
  fallback_message : String,
) -> AutoLaunchError {
  ignore(last_error_code_ffi())
  AutoLaunchError::NativeFailure(
    action~,
    message=last_error_message_or(fallback_message),
  )
}

///|
/// Converts an optional path into a `Result`.
fn optional_path_result(
  path : String?,
  missing_error : AutoLaunchError,
) -> Result[String, AutoLaunchError] {
  match path {
    Some(value) => Ok(value)
    None => Err(missing_error)
  }
}

///|
/// Converts a native "0 means success" status code into `Result[Unit, _]`.
fn unit_result_from_status(
  status : Int,
  action : String,
  fallback_message : String,
) -> Result[Unit, AutoLaunchError] {
  if status == 0 {
    Ok(())
  } else {
    Err(native_failure(action, fallback_message))
  }
}

///|
/// Converts a native tri-state existence status into `Result[Bool, _]`.
fn bool_result_from_status(
  status : Int,
  action : String,
  fallback_message : String,
) -> Result[Bool, AutoLaunchError] {
  match status {
    0 => Ok(false)
    1 => Ok(true)
    _ => Err(native_failure(action, fallback_message))
  }
}

///|
/// Returns the current executable path or a typed discovery error.
fn current_executable_path_result() -> Result[String, AutoLaunchError] {
  optional_path_result(
    decode_optional_text(current_executable_path_ffi()),
    AutoLaunchError::ExecutablePathUnavailable,
  )
}

///|
/// Returns the current home directory or a typed discovery error.
fn home_directory_result() -> Result[String, AutoLaunchError] {
  optional_path_result(
    decode_optional_text(home_directory_ffi()),
    AutoLaunchError::HomeDirectoryUnavailable,
  )
}

///|
/// Writes a text file through the native layer.
fn write_text_file_result(
  path : String,
  contents : String,
) -> Result[Unit, AutoLaunchError] {
  unit_result_from_status(
    write_text_file_ffi(@utf8.encode(path), @utf8.encode(contents)),
    "write file",
    "Failed to write auto-launch entry file",
  )
}

///|
/// Removes a file through the native layer.
fn remove_file_result(path : String) -> Result[Unit, AutoLaunchError] {
  unit_result_from_status(
    remove_file_ffi(@utf8.encode(path)),
    "remove file",
    "Failed to remove auto-launch entry file",
  )
}

///|
/// Checks file existence through the native layer.
fn file_exists_result(path : String) -> Result[Bool, AutoLaunchError] {
  bool_result_from_status(
    file_exists_ffi(@utf8.encode(path)),
    "file exists",
    "Failed to check auto-launch entry file",
  )
}

///|
/// Creates or updates a Windows `Run` registry entry.
fn windows_set_run_entry_result(
  name : String,
  command : String,
) -> Result[Unit, AutoLaunchError] {
  unit_result_from_status(
    windows_set_run_entry_ffi(@utf8.encode(name), @utf8.encode(command)),
    "set windows run entry",
    "Failed to write Windows Run registry value",
  )
}

///|
/// Deletes a Windows `Run` registry entry.
fn windows_delete_run_entry_result(
  name : String,
) -> Result[Unit, AutoLaunchError] {
  unit_result_from_status(
    windows_delete_run_entry_ffi(@utf8.encode(name)),
    "delete windows run entry",
    "Failed to delete Windows Run registry value",
  )
}

///|
/// Checks whether a Windows `Run` registry entry exists.
fn windows_run_entry_exists_result(
  name : String,
) -> Result[Bool, AutoLaunchError] {
  bool_result_from_status(
    windows_run_entry_exists_ffi(@utf8.encode(name)),
    "windows run entry exists",
    "Failed to query Windows Run registry value",
  )
}
