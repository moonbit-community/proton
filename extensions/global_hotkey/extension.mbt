///|
#proton.event(name="activity")
struct GlobalHotkeyActivity {
  operation : String
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="triggered")
struct GlobalHotkeyTriggered {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
async fn emit_command_activity(
  context : @proton_command.AppCommandExtensionContext,
  operation : String,
  accelerator : String,
) -> Unit noraise {
  emit_global_hotkey_activity(context, { operation, accelerator })
}

///|
async fn[Reply] emit_command_result(
  context : @proton_command.AppCommandExtensionContext,
  reply : Reply,
  operation : String,
  accelerator : String,
) -> Reply noraise {
  emit_command_activity(context, operation, accelerator)
  reply
}

///|
#proton.script
fn trigger_poller_script() -> String {
  (
    #|(() => {
    #|  const root = window.__MoonBit__;
    #|  const globalHotkey = root && root.globalHotkey;
    #|  if (!globalHotkey || typeof globalHotkey.drainTriggered !== "function") {
    #|    return;
    #|  }
    #|  if (globalHotkey.__protonTriggerPoller) {
    #|    return;
    #|  }
    #|  globalHotkey.__protonTriggerPoller = window.setInterval(() => {
    #|    globalHotkey.drainTriggered({}).catch(() => {});
    #|  }, 100);
    #|})();
  )
}

///|
/// Registers one global hotkey from a generated app-command extension.
#proton.command(name="register")
async fn register(
  context : @proton_command.AppCommandExtensionContext,
  accelerator : String,
) -> GlobalHotkeyReply raise GlobalHotkeyError {
  emit_command_result(
    context,
    register_hotkey(app_command_manager_handle(), accelerator),
    "register",
    accelerator,
  )
}

///|
/// Unregisters one global hotkey from a generated app-command extension.
#proton.command(name="unregister")
async fn unregister(
  context : @proton_command.AppCommandExtensionContext,
  accelerator : String,
) -> GlobalHotkeyReply raise GlobalHotkeyError {
  emit_command_result(
    context,
    unregister_hotkey(app_command_manager_handle(), accelerator),
    "unregister",
    accelerator,
  )
}

///|
/// Lists registered global hotkeys from a generated app-command extension.
#proton.command(name="list")
fn list(
  _payload : EmptyPayload?,
) -> GlobalHotkeyListReply raise GlobalHotkeyError {
  list_hotkeys(app_command_manager_handle())
}

///|
/// Drains triggered global hotkeys from a generated app-command extension.
#proton.command(name="drainTriggered")
async fn drain_triggered(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> GlobalHotkeyListReply raise GlobalHotkeyError {
  let reply = drain_triggered_hotkeys(app_command_manager_handle())
  for accelerator in reply.accelerators {
    emit_global_hotkey_triggered(context, { accelerator, })
  }
  reply
}
