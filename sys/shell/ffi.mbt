///|
/// Returns whether the native shell backend is available on the current target.
extern "C" fn is_supported_ffi() -> Bool = "mb_shell_is_supported"

///|
/// Opens a target through the native shell. `target` must be UTF-16LE bytes
/// with a trailing wide nul (as produced by `@ffi.to_wstr`).
#borrow(target)
extern "C" fn open_ffi(target : Bytes) -> Bool = "mb_shell_open"

///|
/// Reveals a filesystem item in the native file manager. `path` must be
/// UTF-16LE bytes with a trailing wide nul (as produced by `@ffi.to_wstr`).
#borrow(path)
extern "C" fn reveal_item_ffi(path : Bytes) -> Bool = "mb_shell_reveal_item"

///|
/// Moves a filesystem item to the platform trash/recycle bin. `path` is a
/// UTF-8 byte string with a trailing nul (as produced by `@ffi.to_cstr`).
/// Implemented for Windows, macOS, and Linux.
#borrow(path)
extern "C" fn trash_item_ffi(path : Bytes) -> Bool = "mb_shell_trash_item"

///|
/// Plays the platform's default alert sound.
extern "C" fn beep_ffi() -> Bool = "mb_shell_beep"
