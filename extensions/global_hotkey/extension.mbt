///|
let extension_id = "justjavac/lepus-global-hotkey"

///|
let extension_namespace = "globalHotkey"

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
/// Emits a global-hotkey activity event for JavaScript listeners.
fn emit_activity(
  extension : @core.ExtensionContext,
  operation : String,
  accelerator : String,
) -> Unit {
  extension.emit("activity", { operation, accelerator })
}

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

///|
/// Returns the JavaScript poller script that forwards triggered hotkeys as extension events.
fn trigger_poller_script() -> String {
  (
    #|(() => {
    #|  const moonbit = window.__MoonBit__;
    #|  if (!moonbit || !moonbit.events || typeof moonbit.events["@@emitExtensionEvent"] !== "function") {
    #|    return;
    #|  }
    #|  const state = moonbit["@@state"] && typeof moonbit["@@state"] === "object"
    #|    ? moonbit["@@state"]
    #|    : (moonbit["@@state"] = Object.create(null));
    #|  if (state.globalHotkeyPoller) {
    #|    return;
    #|  }
    #|  state.globalHotkeyPoller = window.setInterval(() => {
    #|    const extension = moonbit.globalHotkey;
    #|    if (!extension || typeof extension.drainTriggered !== "function") {
    #|      return;
    #|    }
    #|    extension.drainTriggered({})
    #|      .then((reply) => {
    #|        if (!reply || !Array.isArray(reply.accelerators)) {
    #|          return;
    #|        }
    #|        for (const accelerator of reply.accelerators) {
    #|          moonbit.events["@@emitExtensionEvent"]("globalHotkey", "triggered", {
    #|            accelerator,
    #|          });
    #|        }
    #|      })
    #|      .catch(() => {});
    #|  }, 150);
    #|})();
  )
}

///|
/// Builds the `globalHotkey` extension for direct installation.
/// Install it manually when trusted local content needs runtime hotkey
/// registration without going through an app registry.
pub fn extension() -> @core.Extension {
  let mut manager : @sys_global_hotkey.GlobalHotkeyManager? = None
  @core.Extension::new(
    extension_id,
    extension_namespace,
    fn(extension) {
      manager = init_manager()

      extension.op_result("register", fn(payload : GlobalHotkeyPayload) {
        register_hotkey(manager, payload.accelerator).map(fn(reply) {
          emit_activity(extension, "register", payload.accelerator)
          reply
        })
      })

      extension.op_result("unregister", fn(payload : GlobalHotkeyPayload) {
        unregister_hotkey(manager, payload.accelerator).map(fn(reply) {
          emit_activity(extension, "unregister", payload.accelerator)
          reply
        })
      })

      extension.op_result("list", fn(_payload : EmptyPayload) {
        Ok(list_hotkeys(manager))
      })

      extension.op_result("drainTriggered", fn(_payload : EmptyPayload) {
        Ok(drain_triggered_hotkeys(manager))
      })
    },
    on_destroy=fn(_extension) {
      destroy_manager(manager)
      manager = None
    },
    scripts=[trigger_poller_script()],
  )
}

///|
/// Builds the declarative `globalHotkey` extension spec.
/// Use this when global hotkeys should be linked through registry-based app
/// composition.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
