///|
struct TrayMenuItemPayload {
  id : String?
  label : String?
  kind : String?
  enabled : Bool?
  checked : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct TrayMenuPayload {
  items : Array[TrayMenuItemPayload]
} derive(ToJson, FromJson, Debug, Eq)

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
struct TrayReply {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct TraySupportReply {
  supported : Bool
  platform : String
  reason : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct TrayEventReply {
  count : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="activity")
struct TrayActivity {
  operation : String
  visible : Bool
  tooltip : String?
  icon : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="click")
struct TrayClickEvent {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="rightClick")
struct TrayRightClickEvent {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="doubleClick")
struct TrayDoubleClickEvent {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="menuItemClick")
struct TrayMenuItemClickEvent {
  item_id : String
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
let app_command_tray_handle : Ref[@sys_tray.Tray?] = Ref(None)

///|
let app_command_tray_visible : Ref[Bool] = Ref(false)

///|
fn platform_label(platform : @sys_tray.Platform) -> String {
  match platform {
    Windows => "windows"
    Linux => "linux"
    MacOS => "macos"
    Unknown => "unknown"
  }
}

///|
fn tray_support() -> TraySupportReply {
  let platform = platform_label(@sys_tray.current_platform())
  match @sys_tray.ensure_supported() {
    Ok(_) => TraySupportReply::{ supported: true, platform, reason: None }
    Err(error) =>
      TraySupportReply::{ supported: false, platform, reason: Some(error) }
  }
}

///|
fn tray_operation_result(
  operation : String,
  result : Result[Bool, String],
) -> Result[Bool, String] {
  match result {
    Ok(visible) => Ok(visible)
    Err(error) => Err(operation + " failed: " + error)
  }
}

///|
fn tray_handle() -> Result[@sys_tray.Tray, String] {
  match app_command_tray_handle.val {
    Some(handle) => Ok(handle)
    None =>
      match @sys_tray.create(identifier="justjavac.proton.tray") {
        Ok(handle) => {
          app_command_tray_handle.val = Some(handle)
          Ok(handle)
        }
        Err(error) => Err("create tray failed: " + error)
      }
  }
}

///|
fn required_text(value : String?, label : String) -> Result[String, String] {
  match value {
    Some(text) =>
      if text.trim().to_owned().is_empty() {
        Err(label + " must not be empty")
      } else {
        Ok(text)
      }
    None => Err(label + " is required")
  }
}

///|
fn optional_json_text(value : Json?, label : String) -> Result[String?, String] {
  match value {
    None | Some(Null) => Ok(None)
    Some(String(text)) => Ok(Some(text))
    _ => Err(label + " must be a string or null")
  }
}

///|
fn menu_items_to_native(
  items : Array[TrayMenuItemPayload],
) -> Result[Array[@sys_tray.TrayMenuItem], String] {
  let native_items : Array[@sys_tray.TrayMenuItem] = []
  for item in items {
    let kind = item.kind.unwrap_or("normal")
    match kind {
      "normal" => {
        let id = match required_text(item.id, "menu item id") {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let label = match required_text(item.label, "menu item label") {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        native_items.push(
          @sys_tray.TrayMenuItem::normal(
            id~,
            label~,
            enabled=item.enabled.unwrap_or(true),
          ),
        )
      }
      "separator" => native_items.push(@sys_tray.TrayMenuItem::separator())
      "checkbox" => {
        let id = match required_text(item.id, "menu item id") {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let label = match required_text(item.label, "menu item label") {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        native_items.push(
          @sys_tray.TrayMenuItem::checkbox(
            id~,
            label~,
            checked=item.checked.unwrap_or(false),
            enabled=item.enabled.unwrap_or(true),
          ),
        )
      }
      _ => return Err("unsupported tray menu item kind: " + kind)
    }
  }
  Ok(native_items)
}

///|
fn menu_payload_to_native(
  menu : TrayMenuPayload,
) -> Result[Array[@sys_tray.TrayMenuItem], String] {
  menu_items_to_native(menu.items)
}

///|
async fn emit_command_activity(
  context : @proton_command.AppCommandExtensionContext,
  operation : String,
  tooltip : String?,
  icon : String?,
) -> Unit {
  emit_tray_activity(context, TrayActivity::{
    operation,
    visible: app_command_tray_visible.val,
    tooltip,
    icon,
  })
}

///|
async fn emit_native_tray_event(
  context : @proton_command.AppCommandExtensionContext,
  event : @sys_tray.TrayEvent,
) -> Unit {
  match event {
    Click =>
      emit_tray_click_event(context, TrayClickEvent::{
        visible: app_command_tray_visible.val,
      })
    RightClick =>
      emit_tray_right_click_event(context, TrayRightClickEvent::{
        visible: app_command_tray_visible.val,
      })
    DoubleClick =>
      emit_tray_double_click_event(context, TrayDoubleClickEvent::{
        visible: app_command_tray_visible.val,
      })
    MenuItemClick(item_id) =>
      emit_tray_menu_item_click_event(context, TrayMenuItemClickEvent::{
        item_id,
        visible: app_command_tray_visible.val,
      })
  }
}

///|
fn destroy_tray(tray_handle : @sys_tray.Tray?) -> Unit {
  match tray_handle {
    Some(handle) => handle.destroy()
    None => ()
  }
  app_command_tray_handle.val = None
  app_command_tray_visible.val = false
}

///|
#proton.script
fn tray_event_poller_script() -> String {
  (
    #|(() => {
    #|  const root = window.__MoonBit__;
    #|  const tray = root && root.tray;
    #|  if (!tray || typeof tray.drainEvents !== "function") {
    #|    return;
    #|  }
    #|  if (tray.__protonEventPoller) {
    #|    return;
    #|  }
    #|  tray.__protonEventPoller = window.setInterval(() => {
    #|    tray.drainEvents({}).catch(() => {});
    #|  }, 100);
    #|})();
  )
}

///|
#proton.destroy
fn cleanup_tray(context : @proton_command.AppCommandExtensionContext) -> Unit {
  ignore(context.extension_id())
  destroy_tray(app_command_tray_handle.val)
}

///|
/// Returns platform support details for JavaScript callers.
#proton.command(name="support")
fn support(_payload : EmptyPayload?) -> TraySupportReply {
  tray_support()
}

///|
/// Shows the native tray icon.
#proton.command(name="show")
async fn show(
  context : @proton_command.AppCommandExtensionContext,
  icon : Json?,
  tooltip : String?,
  menu : TrayMenuPayload?,
) -> Result[TrayReply, String] {
  let icon = match optional_json_text(icon, "icon") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let handle = match tray_handle() {
    Ok(handle) => handle
    Err(error) => return Err(error)
  }
  match icon {
    Some(path) =>
      match
        tray_operation_result("set tray icon", handle.set_icon(Some(path))) {
        Err(error) => return Err(error)
        Ok(visible) => app_command_tray_visible.val = visible
      }
    None => ()
  }
  match menu {
    Some(value) =>
      match menu_payload_to_native(value) {
        Err(error) => return Err(error)
        Ok(native_menu) =>
          match
            tray_operation_result("set tray menu", handle.set_menu(native_menu)) {
            Err(error) => return Err(error)
            Ok(visible) => app_command_tray_visible.val = visible
          }
      }
    None => ()
  }
  match tray_operation_result("show tray", handle.show(tooltip~)) {
    Err(error) => Err(error)
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "show", tooltip, icon)
      Ok(TrayReply::{ visible, })
    }
  }
}

///|
/// Hides the native tray icon.
#proton.command(name="hide")
async fn hide(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[TrayReply, String] {
  match app_command_tray_handle.val {
    None => {
      app_command_tray_visible.val = false
      emit_command_activity(context, "hide", None, None)
      Ok(TrayReply::{ visible: false })
    }
    Some(handle) =>
      match tray_operation_result("hide tray", handle.hide()) {
        Err(error) => Err(error)
        Ok(visible) => {
          app_command_tray_visible.val = visible
          emit_command_activity(context, "hide", None, None)
          Ok(TrayReply::{ visible, })
        }
      }
  }
}

///|
/// Updates the native tray icon.
#proton.command(name="setIcon")
async fn set_icon(
  context : @proton_command.AppCommandExtensionContext,
  icon : Json?,
) -> Result[TrayReply, String] {
  let icon = match optional_json_text(icon, "icon") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let handle = match tray_handle() {
    Ok(handle) => handle
    Err(error) => return Err(error)
  }
  match tray_operation_result("set tray icon", handle.set_icon(icon)) {
    Err(error) => Err(error)
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "setIcon", None, icon)
      Ok(TrayReply::{ visible, })
    }
  }
}

///|
/// Updates the native tray tooltip.
#proton.command(name="setTooltip")
async fn set_tooltip(
  context : @proton_command.AppCommandExtensionContext,
  tooltip : String,
) -> Result[TrayReply, String] {
  let handle = match tray_handle() {
    Ok(handle) => handle
    Err(error) => return Err(error)
  }
  match tray_operation_result("set tray tooltip", handle.set_tooltip(tooltip)) {
    Err(error) => Err(error)
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "setTooltip", Some(tooltip), None)
      Ok(TrayReply::{ visible, })
    }
  }
}

///|
/// Replaces the native tray context menu.
#proton.command(name="setMenu")
async fn set_menu(
  context : @proton_command.AppCommandExtensionContext,
  items : Array[TrayMenuItemPayload],
) -> Result[TrayReply, String] {
  let handle = match tray_handle() {
    Ok(handle) => handle
    Err(error) => return Err(error)
  }
  match menu_items_to_native(items) {
    Err(error) => Err(error)
    Ok(native_menu) =>
      match
        tray_operation_result("set tray menu", handle.set_menu(native_menu)) {
        Err(error) => Err(error)
        Ok(visible) => {
          app_command_tray_visible.val = visible
          emit_command_activity(context, "setMenu", None, None)
          Ok(TrayReply::{ visible, })
        }
      }
  }
}

///|
/// Drains native tray events into JavaScript extension events.
#proton.command(name="drainEvents")
async fn drain_events(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[TrayEventReply, String] {
  match app_command_tray_handle.val {
    None => Ok(TrayEventReply::{ count: 0 })
    Some(handle) => {
      match handle.pump(blocking=false) {
        Ok(_) => ()
        Err(error) => return Err("pump tray failed: " + error)
      }
      let events = handle.drain_events()
      for event in events {
        emit_native_tray_event(context, event)
      }
      Ok(TrayEventReply::{ count: events.length() })
    }
  }
}

///|
/// Destroys the native tray icon.
#proton.command(name="destroy")
async fn destroy(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[TrayReply, String] {
  destroy_tray(app_command_tray_handle.val)
  emit_command_activity(context, "destroy", None, None)
  Ok(TrayReply::{ visible: false })
}
