///|
let windows_icon_error_buffer_length = 1024

///|
let windows_icon_ok = 0

///|
#borrow(executable, icon, error_buffer)
extern "C" fn set_windows_executable_icon_ffi(
  executable : Bytes,
  executable_length : Int,
  icon : Bytes,
  icon_length : Int,
  error_buffer : FixedArray[Byte],
  error_buffer_length : Int,
) -> Int = "proton_package_set_windows_executable_icon"

///|
fn first_windows_icon(icons : Array[String]) -> String? {
  for icon in icons {
    if icon.to_lower().has_suffix(".ico") {
      return Some(icon)
    }
  }
  None
}

///|
async fn stage_windows_icon(plan : PackagePlan, executable : String) -> Unit {
  guard first_windows_icon(plan.icons) is Some(icon) else { return }
  guard @fsutil.path_is_file(icon) else {
    raise PackagePlanError::MissingIcon(path=icon)
  }
  let executable_bytes = @utf8.encode(executable)
  let icon_bytes = @utf8.encode(icon)
  let error_buffer = FixedArray::make(windows_icon_error_buffer_length, b'\x00')
  let status = set_windows_executable_icon_ffi(
    executable_bytes,
    executable_bytes.length(),
    icon_bytes,
    icon_bytes.length(),
    error_buffer,
    error_buffer.length(),
  )
  guard status == windows_icon_ok else {
    raise WindowsPackagingError::ToolFailure(
      stage="embed Windows application icon",
      detail=windows_icon_error_text(error_buffer, status),
    )
  }
}

///|
fn windows_icon_error_text(buffer : FixedArray[Byte], status : Int) -> String {
  let bytes = Bytes::from_array(buffer)
  let end = bytes.find(b"\x00").unwrap_or(bytes.length())
  let detail = @utf8.decode_lossy(bytes[0:end])
  if detail == "" {
    "native icon writer failed with status " + status.to_string()
  } else {
    detail
  }
}
