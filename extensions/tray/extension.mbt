///|
type TrayMenuItemPayload = @tray_contract.TrayMenuItem

///|
type TrayMenuPayload = @tray_contract.TrayMenu

///|
let support_command = @tray_contract.support

///|
let show_command = @tray_contract.show

///|
let hide_command = @tray_contract.hide

///|
let set_icon_command = @tray_contract.set_icon

///|
let set_tooltip_command = @tray_contract.set_tooltip

///|
let set_menu_command = @tray_contract.set_menu

///|
let destroy_command = @tray_contract.destroy

///|
let app_command_tray_handle : Ref[@sys_tray.Tray?] = Ref(None)

///|
let app_command_tray_visible : Ref[Bool] = Ref(false)

///|
let app_command_event_wakeup : Ref[@proton_extension.EventWakeup?] = Ref(None)

///|
fn platform_label(platform : @sys_tray.Platform) -> String {
  match platform {
    Windows => "windows"
    Linux => "linux"
    Macos => "macos"
    Unknown => "unknown"
  }
}

///|
fn tray_support() -> @proton_contract.SupportReply {
  let platform = platform_label(@sys_tray.current_platform())
  match @sys_tray.ensure_supported() {
    Ok(_) =>
      @proton_contract.SupportReply::{
        supported: true,
        platform,
        reason: None,
      }
    Err(error) =>
      @proton_contract.SupportReply::{
        supported: false,
        platform,
        reason: Some(error),
      }
  }
}

///|
fn tray_handle() -> @sys_tray.Tray raise TrayError {
  match app_command_tray_handle.val {
    Some(handle) => handle
    None =>
      match @sys_tray.create(identifier="moonbit-community.proton.tray") {
        Ok(handle) => {
          match app_command_event_wakeup.val {
            Some(wakeup) => handle.set_event_wakeup(wakeup)
            None => ()
          }
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
  context : @proton.CommandContext,
  operation : String,
  tooltip : String?,
  icon : String?,
) -> Unit {
  context.emit(@tray_contract.activity, @tray_contract.TrayActivity::{
    operation,
    visible: app_command_tray_visible.val,
    tooltip,
    icon,
  })
}

///|
fn native_tray_event(
  event : @sys_tray.TrayEvent,
) -> @proton_extension.Event raise {
  match event {
    Click =>
      @proton_extension.event(@tray_contract.click, @tray_contract.TrayClick::{
        visible: app_command_tray_visible.val,
      })
    RightClick =>
      @proton_extension.event(@tray_contract.right_click, @tray_contract.TrayRightClick::{
        visible: app_command_tray_visible.val,
      })
    DoubleClick =>
      @proton_extension.event(@tray_contract.double_click, @tray_contract.TrayDoubleClick::{
        visible: app_command_tray_visible.val,
      })
    MenuItemClick(item_id) =>
      @proton_extension.event(@tray_contract.menu_item_click, @tray_contract.TrayMenuItemClick::{
        item_id,
        visible: app_command_tray_visible.val,
      })
  }
}

///|
fn install_event_wakeup(wakeup : @proton_extension.EventWakeup) -> Unit {
  app_command_event_wakeup.val = Some(wakeup)
  match app_command_tray_handle.val {
    Some(handle) => handle.set_event_wakeup(wakeup)
    None => ()
  }
}

///|
fn drain_native_events() -> Array[@proton_extension.Event] raise {
  match app_command_tray_handle.val {
    None => []
    Some(handle) => handle.drain_events().map(native_tray_event)
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
fn cleanup_tray() -> Unit {
  destroy_tray(app_command_tray_handle.val)
  app_command_event_wakeup.val = None
}

///|
/// Returns platform support details for JavaScript callers.
#proton.command(contract=support_command)
fn support(
  _request : @proton_contract.EmptyRequest,
) -> @proton_contract.SupportReply {
  tray_support()
}

///|
/// Shows the native tray icon.
#proton.command(contract=show_command)
async fn show(
  context : @proton.CommandContext,
  request : @tray_contract.ShowRequest,
) -> @tray_contract.TrayReply {
  let icon = optional_json_text(request.icon, "icon")
  let handle = tray_handle()
  match icon {
    Some(path) =>
      app_command_tray_visible.val = set_tray_icon(handle, Some(path))
    None => ()
  }
  match request.menu {
    Some(value) =>
      app_command_tray_visible.val = set_tray_menu(
        handle,
        menu_payload_to_native(value),
      )
    None => ()
  }
  match handle.show(tooltip=request.tooltip) {
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "show", request.tooltip, icon)
      @tray_contract.TrayReply::{ visible, }
    }
    Err(error) => raise ShowFailed(detail=error)
  }
}

///|
/// Hides the native tray icon.
#proton.command(contract=hide_command)
async fn hide(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @tray_contract.TrayReply {
  match app_command_tray_handle.val {
    None => {
      app_command_tray_visible.val = false
      emit_command_activity(context, "hide", None, None)
      @tray_contract.TrayReply::{ visible: false, }
    }
    Some(handle) =>
      match handle.hide() {
        Ok(visible) => {
          app_command_tray_visible.val = visible
          emit_command_activity(context, "hide", None, None)
          @tray_contract.TrayReply::{ visible, }
        }
        Err(error) => raise HideFailed(detail=error)
      }
  }
}

///|
/// Updates the native tray icon.
#proton.command(contract=set_icon_command)
async fn set_icon(
  context : @proton.CommandContext,
  request : @tray_contract.SetIconRequest,
) -> @tray_contract.TrayReply {
  let icon = optional_json_text(request.icon, "icon")
  let visible = set_tray_icon(tray_handle(), icon)
  app_command_tray_visible.val = visible
  emit_command_activity(context, "setIcon", None, icon)
  @tray_contract.TrayReply::{ visible, }
}

///|
/// Updates the native tray tooltip.
#proton.command(contract=set_tooltip_command)
async fn set_tooltip(
  context : @proton.CommandContext,
  request : @tray_contract.SetTooltipRequest,
) -> @tray_contract.TrayReply {
  match tray_handle().set_tooltip(request.tooltip) {
    Ok(visible) => {
      app_command_tray_visible.val = visible
      emit_command_activity(context, "setTooltip", Some(request.tooltip), None)
      @tray_contract.TrayReply::{ visible, }
    }
    Err(error) => raise SetTooltipFailed(detail=error)
  }
}

///|
/// Replaces the native tray context menu.
#proton.command(contract=set_menu_command)
async fn set_menu(
  context : @proton.CommandContext,
  request : @tray_contract.SetMenuRequest,
) -> @tray_contract.TrayReply {
  let visible = set_tray_menu(
    tray_handle(),
    menu_items_to_native(request.items),
  )
  app_command_tray_visible.val = visible
  emit_command_activity(context, "setMenu", None, None)
  @tray_contract.TrayReply::{ visible, }
}

///|
/// Destroys the native tray icon.
#proton.command(contract=destroy_command)
async fn destroy(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @tray_contract.TrayReply {
  destroy_tray(app_command_tray_handle.val)
  emit_command_activity(context, "destroy", None, None)
  @tray_contract.TrayReply::{ visible: false, }
}

///|
let extension_definition : @proton_extension.Extension = @proton_extension.typed(
  @tray_contract.extension,
  generated_extension_command_routes(),
  fn(registrar) raise { register_commands(registrar) },
  event_source=@proton_extension.event_source(
    wakeup => install_event_wakeup(wakeup),
    () => cleanup_tray(),
    () => drain_native_events(),
  ),
)

///|
/// Grants tray commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension_definition)
}
