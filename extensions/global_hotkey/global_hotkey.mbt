///|
let app_command_manager : Ref[@sys_global_hotkey.GlobalHotkeyManager?] = Ref(
  None,
)

///|
/// Verifies that global hotkeys are available on the current platform.
fn ensure_supported() -> Unit raise GlobalHotkeyError {
  match @sys_global_hotkey.ensure_supported() {
    Ok(_) => ()
    Err(error) => raise Unsupported(detail=error)
  }
}

///|
/// Creates the native hotkey manager when support is available.
fn init_manager() -> @sys_global_hotkey.GlobalHotkeyManager raise GlobalHotkeyError {
  ensure_supported()
  match @sys_global_hotkey.create() {
    Ok(handle) => handle
    Err(error) => raise ManagerInitializationFailed(detail=error)
  }
}

///|
fn app_command_manager_handle() -> @sys_global_hotkey.GlobalHotkeyManager raise GlobalHotkeyError {
  match app_command_manager.val {
    Some(handle) => handle
    None => {
      let handle = init_manager()
      app_command_manager.val = Some(handle)
      handle
    }
  }
}

///|
/// Returns the selected accelerator list or an empty result when the manager is unavailable.
fn list_or_empty(
  manager : @sys_global_hotkey.GlobalHotkeyManager,
  selector : (@sys_global_hotkey.GlobalHotkeyManager) -> Array[String],
) -> @global_hotkey_contract.GlobalHotkeyListReply {
  @global_hotkey_contract.GlobalHotkeyListReply::{
    accelerators: selector(manager),
  }
}

///|
fn register_hotkey(
  manager : @sys_global_hotkey.GlobalHotkeyManager,
  accelerator : String,
) -> @global_hotkey_contract.GlobalHotkeyReply raise GlobalHotkeyError {
  match manager.register(accelerator) {
    Ok(registered) => @global_hotkey_contract.GlobalHotkeyReply::{ registered, }
    Err(error) => raise RegistrationFailed(accelerator~, detail=error)
  }
}

///|
fn unregister_hotkey(
  manager : @sys_global_hotkey.GlobalHotkeyManager,
  accelerator : String,
) -> @global_hotkey_contract.GlobalHotkeyReply raise GlobalHotkeyError {
  match manager.unregister(accelerator) {
    Ok(registered) => @global_hotkey_contract.GlobalHotkeyReply::{ registered, }
    Err(error) => raise UnregistrationFailed(accelerator~, detail=error)
  }
}

///|
fn list_hotkeys(
  manager : @sys_global_hotkey.GlobalHotkeyManager,
) -> @global_hotkey_contract.GlobalHotkeyListReply {
  list_or_empty(manager, fn(handle) { handle.list() })
}

///|
fn drain_triggered_hotkeys(
  manager : @sys_global_hotkey.GlobalHotkeyManager,
) -> @global_hotkey_contract.GlobalHotkeyListReply {
  list_or_empty(manager, fn(handle) { handle.drain_triggered() })
}
