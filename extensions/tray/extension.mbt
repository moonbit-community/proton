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
fn tray_handle() -> @sys_tray.Tray raise TrayError {
  match app_command_tray_handle.val {
    Some(handle) => handle
    None =>
      match @sys_tray.create(identifier="justjavac.proton.tray") {
        Ok(handle) => {
          app_command_tray_handle.val = Some(handle)
          handle
        }
        Err(error) => raise CreateFailed(detail=error)
      }
  }
}

///|
fn required_text(value : String?, label : String) -> String raise TrayError {
  match value {
    Some(text) =>
      if text.trim().to_owned().is_empty() {
        raise EmptyField(field=label)
      } else {
        text
      }
    None => raise MissingField(field=label)
  }
}

///|
fn optional_json_text(value : Json?, label : String) -> String? raise TrayError {
  match value {
    None | Some(Null) => None
    Some(String(text)) => Some(text)
    _ => raise InvalidFieldType(field=label, expected="a string or null")
  }
}

///|
fn menu_items_to_native(
  items : Array[TrayMenuItemPayload],
) -> Array[@sys_tray.TrayMenuItem] raise TrayError {
  let native_items : Array[@sys_tray.TrayMenuItem] = []
  for item in items {
    let kind = item.kind.unwrap_or("normal")
    match kind {
      "normal" => {
        let id = required_text(item.id, "menu item id")
        let label = required_text(item.label, "menu item label")
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
        let id = required_text(item.id, "menu item id")
        let label = required_text(item.label, "menu item label")
        native_items.push(
          @sys_tray.TrayMenuItem::checkbox(
            id~,
            label~,
            checked=item.checked.unwrap_or(false),
            enabled=item.enabled.unwrap_or(true),
          ),
        )
      }
      _ => raise UnsupportedMenuItemKind(kind~)
    }
  }
  native_items
}

///|
fn menu_payload_to_native(
  menu : TrayMenuPayload,
) -> Array[@sys_tray.TrayMenuItem] raise TrayError {
  menu_items_to_native(menu.items)
}

///|
fn set_tray_icon(
  handle : @sys_tray.Tray,
  icon : String?,
) -> Bool raise TrayError {
  match handle.set_icon(icon) {
    Ok(visible) => visible
    Err(error) => raise SetIconFailed(detail=error)
  }
}

///|
fn set_tray_menu(
  handle : @sys_tray.Tray,
  menu : Array[@sys_tray.TrayMenuItem],
) -> Bool raise TrayError {
  match handle.set_menu(menu) {
    Ok(visible) => visible
    Err(error) => raise SetMenuFailed(detail=error)
  }
}

///|
async fn emit_command_activity(
  context : @proton_command.AppCommandExtensionContext,
  operation : String,
  tooltip : String?,
  icon : String?,
) -> Unit noraise {
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
) -> Unit noraise {
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
) -> TrayReply raise TrayError {
  let icon = optional_json_text(icon, "icon")
  let handle = tray_handle()
  match icon {
    Some(path) =>
      app_command_tray_visible.val = set_tray_icon(handle, Some(path))
    None => ()
  }
  match menu {
    Some(value) =>
      app_command_tray_visible.val = set_tray_menu(
        handle,
        menu_payload_to_native(value),
      )
    None => ()
  }
  match handle.show(tooltip~) {
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "show", tooltip, icon)
      TrayReply::{ visible, }
    }
    Err(error) => raise ShowFailed(detail=error)
  }
}

///|
/// Hides the native tray icon.
#proton.command(name="hide")
async fn hide(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> TrayReply raise TrayError {
  match app_command_tray_handle.val {
    None => {
      app_command_tray_visible.val = false
      emit_command_activity(context, "hide", None, None)
      TrayReply::{ visible: false }
    }
    Some(handle) =>
      match handle.hide() {
        Ok(visible) => {
          app_command_tray_visible.val = visible
          emit_command_activity(context, "hide", None, None)
          TrayReply::{ visible, }
        }
        Err(error) => raise HideFailed(detail=error)
      }
  }
}

///|
/// Updates the native tray icon.
#proton.command(name="setIcon")
async fn set_icon(
  context : @proton_command.AppCommandExtensionContext,
  icon : Json?,
) -> TrayReply raise TrayError {
  let icon = optional_json_text(icon, "icon")
  let visible = set_tray_icon(tray_handle(), icon)
  app_command_tray_visible.val = visible
  emit_command_activity(context, "setIcon", None, icon)
  TrayReply::{ visible, }
}

///|
/// Updates the native tray tooltip.
#proton.command(name="setTooltip")
async fn set_tooltip(
  context : @proton_command.AppCommandExtensionContext,
  tooltip : String,
) -> TrayReply raise TrayError {
  match tray_handle().set_tooltip(tooltip) {
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "setTooltip", Some(tooltip), None)
      TrayReply::{ visible, }
    }
    Err(error) => raise SetTooltipFailed(detail=error)
  }
}

///|
/// Replaces the native tray context menu.
#proton.command(name="setMenu")
async fn set_menu(
  context : @proton_command.AppCommandExtensionContext,
  items : Array[TrayMenuItemPayload],
) -> TrayReply raise TrayError {
  let visible = set_tray_menu(tray_handle(), menu_items_to_native(items))
  app_command_tray_visible.val = visible
  emit_command_activity(context, "setMenu", None, None)
  TrayReply::{ visible, }
}

///|
/// Drains native tray events into JavaScript extension events.
#proton.command(name="drainEvents")
async fn drain_events(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> TrayEventReply raise TrayError {
  match app_command_tray_handle.val {
    None => TrayEventReply::{ count: 0 }
    Some(handle) => {
      match handle.pump(blocking=false) {
        Ok(_) => ()
        Err(error) => raise PumpFailed(detail=error)
      }
      let events = handle.drain_events()
      for event in events {
        emit_native_tray_event(context, event)
      }
      TrayEventReply::{ count: events.length() }
    }
  }
}

///|
/// Destroys the native tray icon.
#proton.command(name="destroy")
async fn destroy(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> TrayReply {
  destroy_tray(app_command_tray_handle.val)
  emit_command_activity(context, "destroy", None, None)
  TrayReply::{ visible: false }
}
