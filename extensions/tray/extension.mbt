///|
struct TrayShowPayload {
  tooltip : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct TrayTooltipPayload {
  tooltip : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
struct TrayReply {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#lepus.event(name="activity")
struct TrayActivity {
  operation : String
  tooltip : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
let app_command_tray_handle : Ref[@sys_tray.Tray?] = Ref(None)

///|
/// Verifies that tray support is available on the current platform.
fn ensure_supported() -> Result[Unit, String] {
  @sys_tray.ensure_supported()
}

///|
/// Creates the native tray handle for this extension when supported.
fn init_tray() -> @sys_tray.Tray? {
  match ensure_supported() {
    Ok(_) =>
      match @sys_tray.create(identifier="justjavac.lepus.tray") {
        Ok(handle) => Some(handle)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
/// Runs a tray operation with the initialized tray handle when available.
fn[Reply] with_tray_handle(
  tray_handle : @sys_tray.Tray?,
  callback : (@sys_tray.Tray) -> Result[Reply, String],
) -> Result[Reply, String] {
  ensure_supported().bind(fn(_) {
    match tray_handle {
      Some(handle) => callback(handle)
      None => Err("tray extension failed to initialize")
    }
  })
}

///|
/// Destroys the native tray handle when one was created.
fn destroy_tray(tray_handle : @sys_tray.Tray?) -> Unit {
  match tray_handle {
    Some(handle) => handle.destroy()
    None => ()
  }
}

///|
/// Returns the app-command tray handle, initializing it when needed.
fn tray_handle() -> @sys_tray.Tray? {
  match app_command_tray_handle.val {
    Some(handle) => Some(handle)
    None => {
      let handle = init_tray()
      app_command_tray_handle.val = handle
      handle
    }
  }
}

///|
/// Destroys the app-command tray handle.
#lepus.destroy
fn cleanup_tray(context : @lepus_command.AppCommandExtensionContext) -> Unit {
  ignore(context.extension_id())
  destroy_tray(app_command_tray_handle.val)
  app_command_tray_handle.val = None
}

///|
/// Shows the native tray icon from a generated app-command extension.
#lepus.command(name="show")
async fn show(
  context : @lepus_command.AppCommandExtensionContext,
  tooltip : String?,
) -> Result[TrayReply, String] {
  match with_tray_handle(tray_handle(), fn(handle) { handle.show(tooltip~) }) {
    Err(error) => Err(error)
    Ok(visible) => {
      emit_tray_activity(context, TrayActivity::{ operation: "show", tooltip })
      Ok(TrayReply::{ visible, })
    }
  }
}

///|
/// Hides the native tray icon from a generated app-command extension.
#lepus.command(name="hide")
async fn hide(
  context : @lepus_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[TrayReply, String] {
  match with_tray_handle(tray_handle(), fn(handle) { handle.hide() }) {
    Err(error) => Err(error)
    Ok(visible) => {
      emit_tray_activity(context, TrayActivity::{
        operation: "hide",
        tooltip: None,
      })
      Ok(TrayReply::{ visible, })
    }
  }
}

///|
/// Updates the native tray tooltip from a generated app-command extension.
#lepus.command(name="setTooltip")
async fn set_tooltip(
  context : @lepus_command.AppCommandExtensionContext,
  tooltip : String,
) -> Result[TrayReply, String] {
  match
    with_tray_handle(tray_handle(), fn(handle) { handle.set_tooltip(tooltip) }) {
    Err(error) => Err(error)
    Ok(visible) => {
      emit_tray_activity(context, TrayActivity::{
        operation: "setTooltip",
        tooltip: Some(tooltip),
      })
      Ok(TrayReply::{ visible, })
    }
  }
}
