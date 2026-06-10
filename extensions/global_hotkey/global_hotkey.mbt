///|
struct GlobalHotkeyPayload {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
struct GlobalHotkeyReply {
  registered : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct GlobalHotkeyListReply {
  accelerators : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
let app_command_manager : Ref[@sys_global_hotkey.GlobalHotkeyManager?] = Ref(
  None,
)

///|
/// Verifies that global hotkeys are available on the current platform.
fn ensure_supported() -> Result[Unit, String] {
  @sys_global_hotkey.ensure_supported()
}

///|
/// Creates the native hotkey manager when support is available.
fn init_manager() -> @sys_global_hotkey.GlobalHotkeyManager? {
  match ensure_supported() {
    Ok(_) =>
      match @sys_global_hotkey.create() {
        Ok(handle) => Some(handle)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
fn app_command_manager_handle() -> @sys_global_hotkey.GlobalHotkeyManager? {
  match app_command_manager.val {
    Some(handle) => Some(handle)
    None => {
      let handle = init_manager()
      app_command_manager.val = handle
      handle
    }
  }
}

///|
/// Runs a hotkey operation with the initialized manager when available.
fn[Reply] with_manager(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
  callback : (@sys_global_hotkey.GlobalHotkeyManager) -> Result[Reply, String],
) -> Result[Reply, String] {
  ensure_supported().bind(fn(_) {
    match manager {
      Some(handle) => callback(handle)
      None => Err("globalHotkey extension failed to initialize")
    }
  })
}

///|
/// Returns the selected accelerator list or an empty result when the manager is unavailable.
fn list_or_empty(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
  selector : (@sys_global_hotkey.GlobalHotkeyManager) -> Array[String],
) -> GlobalHotkeyListReply {
  match manager {
    Some(handle) => { accelerators: selector(handle) }
    None => { accelerators: [] }
  }
}

///|
fn register_hotkey(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
  accelerator : String,
) -> Result[GlobalHotkeyReply, String] {
  with_manager(manager, fn(handle) {
    handle.register(accelerator).map(fn(registered) { { registered, } })
  })
}

///|
fn unregister_hotkey(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
  accelerator : String,
) -> Result[GlobalHotkeyReply, String] {
  with_manager(manager, fn(handle) {
    handle.unregister(accelerator).map(fn(registered) { { registered, } })
  })
}

///|
fn list_hotkeys(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
) -> GlobalHotkeyListReply {
  list_or_empty(manager, fn(handle) { handle.list() })
}

///|
fn drain_triggered_hotkeys(
  manager : @sys_global_hotkey.GlobalHotkeyManager?,
) -> GlobalHotkeyListReply {
  list_or_empty(manager, fn(handle) { handle.drain_triggered() })
}
