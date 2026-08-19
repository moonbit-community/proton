///|
let windows_icon_error_buffer_length = 1024

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
async fn stage_windows_icon(spec : PackageSpec, executable : String) -> Unit {
  guard first_windows_icon(spec.icons) is Some(icon) else { return }
  guard path_is_file(icon) else {
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
  guard status == 0 else {
    let bytes = Bytes::from_array(error_buffer)
    let end = bytes.find(b"\x00").unwrap_or(bytes.length())
    let detail = @utf8.decode_lossy(bytes[0:end])
    raise WindowsPackagingError::ToolFailure(
      stage="embed Windows application icon",
      detail=if detail == "" {
        "native icon writer failed with status " + status.to_string()
      } else {
        detail
      },
    )
  }
}
