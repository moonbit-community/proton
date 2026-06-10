///|
#lepus.event(name="activity")
struct GlobalHotkeyActivity {
  operation : String
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
#lepus.event(name="triggered")
struct GlobalHotkeyTriggered {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
async fn emit_command_activity(
  context : @app.AppCommandExtensionContext,
  operation : String,
  accelerator : String,
) -> Unit {
  emit_global_hotkey_activity(context, { operation, accelerator })
}

///|
async fn[Reply] emit_command_result(
  context : @app.AppCommandExtensionContext,
  result : Result[Reply, String],
  operation : String,
  accelerator : String,
) -> Result[Reply, String] {
  match result {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_command_activity(context, operation, accelerator)
      Ok(reply)
    }
  }
}

///|
#lepus.script
fn trigger_poller_script() -> String {
  (
    #|(() => {
    #|  const root = window.__MoonBit__;
    #|  const globalHotkey = root && root.globalHotkey;
    #|  if (!globalHotkey || typeof globalHotkey.drainTriggered !== "function") {
    #|    return;
    #|  }
    #|  if (globalHotkey.__lepusTriggerPoller) {
    #|    return;
    #|  }
    #|  globalHotkey.__lepusTriggerPoller = window.setInterval(() => {
    #|    globalHotkey.drainTriggered({}).catch(() => {});
    #|  }, 100);
    #|})();
  )
}

///|
/// Registers one global hotkey from a generated app-command extension.
#lepus.command(name="register")
async fn register(
  context : @app.AppCommandExtensionContext,
  accelerator : String,
) -> Result[GlobalHotkeyReply, String] {
  emit_command_result(
    context,
    register_hotkey(app_command_manager_handle(), accelerator),
    "register",
    accelerator,
  )
}

///|
/// Unregisters one global hotkey from a generated app-command extension.
#lepus.command(name="unregister")
async fn unregister(
  context : @app.AppCommandExtensionContext,
  accelerator : String,
) -> Result[GlobalHotkeyReply, String] {
  emit_command_result(
    context,
    unregister_hotkey(app_command_manager_handle(), accelerator),
    "unregister",
    accelerator,
  )
}

///|
/// Lists registered global hotkeys from a generated app-command extension.
#lepus.command(name="list")
fn list(_payload : EmptyPayload?) -> GlobalHotkeyListReply {
  list_hotkeys(app_command_manager_handle())
}

///|
/// Drains triggered global hotkeys from a generated app-command extension.
#lepus.command(name="drainTriggered")
async fn drain_triggered(
  context : @app.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> GlobalHotkeyListReply {
  let reply = drain_triggered_hotkeys(app_command_manager_handle())
  for accelerator in reply.accelerators {
    emit_global_hotkey_triggered(context, { accelerator, })
  }
  reply
}
