///|
let register_command = @global_hotkey_contract.register

///|
let unregister_command = @global_hotkey_contract.unregister

///|
let list_command = @global_hotkey_contract.list

///|
async fn emit_command_activity(
  context : @proton.CommandContext,
  operation : String,
  accelerator : String,
) -> Unit {
  context.emit(@global_hotkey_contract.activity, @global_hotkey_contract.GlobalHotkeyActivity::{
    operation,
    accelerator,
  })
}

///|
async fn[Reply] emit_command_result(
  context : @proton.CommandContext,
  reply : Reply,
  operation : String,
  accelerator : String,
) -> Reply {
  emit_command_activity(context, operation, accelerator)
  reply
}

///|
/// Registers one global hotkey from a generated app-command extension.
#proton.command(contract=register_command)
async fn register(
  context : @proton.CommandContext,
  request : @global_hotkey_contract.GlobalHotkeyRequest,
) -> @global_hotkey_contract.GlobalHotkeyReply {
  emit_command_result(
    context,
    register_hotkey(app_command_manager_handle(), request.accelerator),
    "register",
    request.accelerator,
  )
}

///|
/// Unregisters one global hotkey from a generated app-command extension.
#proton.command(contract=unregister_command)
async fn unregister(
  context : @proton.CommandContext,
  request : @global_hotkey_contract.GlobalHotkeyRequest,
) -> @global_hotkey_contract.GlobalHotkeyReply {
  emit_command_result(
    context,
    unregister_hotkey(app_command_manager_handle(), request.accelerator),
    "unregister",
    request.accelerator,
  )
}

///|
/// Lists registered global hotkeys from a generated app-command extension.
#proton.command(contract=list_command)
fn list(
  _request : @proton_contract.EmptyRequest,
) -> @global_hotkey_contract.GlobalHotkeyListReply raise GlobalHotkeyError {
  list_hotkeys(app_command_manager_handle())
}

///|
fn drain_events() -> Array[@proton_extension.Event] raise {
  let events : Array[@proton_extension.Event] = []
  match app_command_manager.val {
    Some(manager) =>
      for accelerator in manager.drain_triggered() {
        events.push(
          @proton_extension.event(@global_hotkey_contract.triggered, @global_hotkey_contract.GlobalHotkeyTriggered::{
            accelerator,
          }),
        )
      }
    None => ()
  }
  events
}

///|
let extension_definition : @proton_extension.Extension = @proton_extension.typed(
  @global_hotkey_contract.extension,
  generated_extension_command_routes(),
  fn(registrar) raise { register_commands(registrar) },
  event_source=@proton_extension.event_source(
    wakeup => install_event_wakeup(wakeup),
    () => cleanup_manager(),
    () => drain_events(),
  ),
)

///|
/// Grants global-hotkey commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension_definition)
}
