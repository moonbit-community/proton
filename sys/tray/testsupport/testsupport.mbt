///|
/// Writes the built-in BMP fixture to a temporary file and returns its path.
extern "C" fn test_icon_path_ffi() -> Bytes = "moonbit_tray_test_icon_path"

///|
#borrow(path)
extern "C" fn test_remove_file_ffi(path : Bytes) -> Bool = "moonbit_tray_test_remove_file"

///|
/// Creates the temporary test icon fixture and returns its path bytes.
///
/// The returned bytes hold the file system path of a freshly written BMP
/// icon, or an empty payload when the fixture could not be created.
pub fn make_test_icon_path() -> Bytes {
  test_icon_path_ffi()
}

///|
/// Removes a file previously created for tests.
///
/// Returns whether the file was removed successfully.
pub fn remove_test_file(path : String) -> Bool {
  test_remove_file_ffi(@ffi.to_cstr(path))
}
