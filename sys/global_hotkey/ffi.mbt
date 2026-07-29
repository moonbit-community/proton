///|
/// Represents the opaque native backend handle owned by `GlobalHotkeyManager`.
///
/// Package users do not inspect values of this type directly. It exists so the
/// manager can retain the foreign state returned by the platform backend.
#external
pub type GlobalHotkeyState

///|
/// Queries whether a backend is currently available on this native target.
extern "C" fn platform_supported_ffi() -> Bool = "mb_global_hotkey_platform_supported"

///|
/// Allocates a backend state object for polling global hotkeys.
extern "C" fn create_state_ffi() -> GlobalHotkeyState = "mb_global_hotkey_create"

///|
/// Releases every native resource associated with a backend state.
extern "C" fn destroy_state_ffi(state : GlobalHotkeyState) -> Unit = "mb_global_hotkey_destroy"

///|
/// Checks whether an external state pointer is null.
extern "C" fn state_is_null_ffi(state : GlobalHotkeyState) -> Bool = "moonbit_is_null"

///|
/// Registers a parsed hotkey against the backend.
#borrow(key_name)
extern "C" fn register_hotkey_ffi(
  state : GlobalHotkeyState,
  id : Int,
  modifiers : Int,
  key_name : Bytes,
) -> Int = "mb_global_hotkey_register"

///|
/// Unregisters a previously registered hotkey id from the backend.
extern "C" fn unregister_hotkey_ffi(state : GlobalHotkeyState, id : Int) -> Int = "mb_global_hotkey_unregister"

///|
/// Pops the next triggered hotkey id from the backend queue.
extern "C" fn take_triggered_id_ffi(state : GlobalHotkeyState) -> Int = "mb_global_hotkey_take_triggered_id"

///|
/// Returns the last backend error message as UTF-8 bytes.
extern "C" fn last_error_message_ffi() -> Bytes = "mb_global_hotkey_last_error_message"
