///|
/// Represents a system tray handle created by this package.
///
/// A `Tray` tracks the user-visible state that the MoonBit layer believes is
/// active, including whether the tray is currently visible, which tooltip is
/// being shown, and which icon path was last requested. The underlying native
/// resources are released by calling `destroy()`.
pub struct Tray {
  priv mut handle : Int64
  priv mut native : Bool
  priv platform : Platform
  priv identifier : String
  priv mut icon : String?
  priv mut tooltip : String
  priv mut menu : Array[TrayMenuItem]
  priv mut events : Array[TrayEvent]
  priv mut visible : Bool
  priv mut destroyed : Bool
}

///|
/// Kind of context-menu item supported by tray v1.
pub(all) enum TrayMenuItemKind {
  Normal
  Separator
  Checkbox
  Submenu
} derive(Debug, Eq)

///|
pub extend TrayMenuItemKind with Eq::{not_equal, equal}

///|
pub extend TrayMenuItemKind with Debug::{to_repr}

///|
/// One tray context-menu item.
///
/// Use `TrayMenuItem::normal`, `TrayMenuItem::separator`, and
/// `TrayMenuItem::checkbox` to build clickable items. Use
/// `TrayMenuItem::submenu` to group nested items. Clickable item ids must be
/// unique across the whole menu tree.
pub(all) enum TrayMenuItem {
  Normal(id~ : String, label~ : String, enabled~ : Bool)
  Separator
  Checkbox(id~ : String, label~ : String, checked~ : Bool, enabled~ : Bool)
  Submenu(label~ : String, items~ : Array[TrayMenuItem], enabled~ : Bool)
} derive(Debug, Eq)

///|
pub extend TrayMenuItem with Eq::{not_equal, equal}

///|
pub extend TrayMenuItem with Debug::{to_repr}

///|
/// Event emitted by the native tray backend.
pub(all) enum TrayEvent {
  Click
  RightClick
  DoubleClick
  MenuItemClick(String)
} derive(Debug, Eq)

///|
pub extend TrayEvent with Eq::{not_equal, equal}

///|
pub extend TrayEvent with Debug::{to_repr}

///|
/// Builds a normal clickable menu item.
pub fn TrayMenuItem::normal(
  id~ : String,
  label~ : String,
  enabled? : Bool = true,
) -> TrayMenuItem {
  Normal(id~, label~, enabled~)
}

///|
/// Builds a separator menu item.
pub fn TrayMenuItem::separator() -> TrayMenuItem {
  Separator
}

///|
/// Builds a checkbox menu item.
pub fn TrayMenuItem::checkbox(
  id~ : String,
  label~ : String,
  checked? : Bool = false,
  enabled? : Bool = true,
) -> TrayMenuItem {
  Checkbox(id~, label~, checked~, enabled~)
}

///|
/// Builds a submenu containing nested menu items.
pub fn TrayMenuItem::submenu(
  label~ : String,
  items~ : Array[TrayMenuItem],
  enabled? : Bool = true,
) -> TrayMenuItem {
  Submenu(label~, items~, enabled~)
}

///|
/// Returns the item kind.
pub fn TrayMenuItem::kind(self : TrayMenuItem) -> TrayMenuItemKind {
  match self {
    Normal(_) => Normal
    Separator => Separator
    Checkbox(_) => Checkbox
    Submenu(_) => Submenu
  }
}

///|
/// Returns the wire-format event name for a tray event.
pub fn TrayEvent::event_name(self : TrayEvent) -> String {
  match self {
    Click => "click"
    RightClick => "rightClick"
    DoubleClick => "doubleClick"
    MenuItemClick(_) => "menuItemClick"
  }
}

///|
/// Returns the clicked menu item id for `MenuItemClick` events.
pub fn TrayEvent::item_id(self : TrayEvent) -> String? {
  match self {
    MenuItemClick(id) => Some(id)
    _ => None
  }
}

///|
/// Returns whether the native backend can create tray instances on the current
/// machine.
///
/// On Windows this is expected to be `true`. On other platforms, or when the
/// required desktop runtime is unavailable, this returns `false`. This probe is
/// side-effect free from the MoonBit caller's perspective and is useful for
/// gating UI paths that would otherwise call `create()`.
///
/// This function answers only whether tray support appears available right now;
/// it does not allocate a tray handle or make one visible. If you need a human
/// readable explanation for a `false` result, call `ensure_supported()` instead.
///
/// # Example
/// ```mbt check
/// test "is_supported probes capability without creating a tray" {
///   let _ : Bool = is_supported()
/// }
/// ```
pub fn is_supported() -> Bool {
  is_supported_ffi()
}

///|
/// Validates that the native backend is available before any tray is created.
///
/// Use this when an application wants to show an actionable startup error
/// instead of deferring the failure until `create()`. The error string is
/// produced by the native backend when available, so callers can surface a
/// platform-specific explanation to users.
///
/// Returns `Ok(())` when tray creation should be possible on the current
/// machine. Returns `Err(message)` when the backend is missing, the desktop
/// runtime is unavailable, or the platform is unsupported.
pub fn ensure_supported() -> Result[Unit, String] {
  if is_supported() {
    Ok(())
  } else {
    Err(support_error_message())
  }
}

///|
/// Creates a tray handle with an optional icon path and initial tooltip.
///
/// - `identifier` should be a stable, non-empty id for the tray instance.
/// - `icon` may be `None` to request the platform default tray icon.
/// - `tooltip` becomes the initial hover text when the platform supports it.
///
/// The returned handle starts hidden, so callers can finish any last setup and
/// then call `show()`. Empty or whitespace-only identifiers are normalized back
/// to `default_identifier()`, and failures include the latest native error when
/// the backend provides one.
///
/// On success this returns `Ok(tray)` with a live handle that can be shown,
/// hidden, updated, pumped, and eventually destroyed. On failure this returns
/// `Err(message)` with either the support-probe failure or the most recent
/// backend creation error.
///
/// Native tray operations, including `destroy()`, must run on the thread that
/// called `create()`; macOS already required this, and it is now enforced on
/// all platforms.
///
/// # Example
/// ```mbt nocheck
/// let tray = @proton_tray.create(icon=Some("/path/to/icon.png"), tooltip="My App").unwrap()
/// let _ = tray.show()
/// // ... run the application event loop, calling `tray.pump()` as needed ...
/// tray.destroy()
/// ```
pub fn create(
  identifier? : String = default_identifier(),
  icon? : String? = None,
  tooltip? : String = "",
) -> Result[Tray, String] {
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => {
      let normalized_identifier = normalize_identifier(identifier)
      match validate_c_text("identifier", normalized_identifier) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match validate_optional_c_text("icon", icon) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match validate_c_text("tooltip", tooltip) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let handle = create_state_ffi(
        encode_text(normalized_identifier),
        encode_optional_text(icon),
        encode_text(tooltip),
      )
      if handle == zero_handle() {
        Err(
          decode_bytes(last_create_error_ffi()).unwrap_or("tray.create failed"),
        )
      } else {
        Ok({
          handle,
          native: true,
          platform: current_platform(),
          identifier: normalized_identifier,
          icon,
          tooltip,
          menu: [],
          events: [],
          visible: false,
          destroyed: false,
        })
      }
    }
  }
}

///|
/// Returns the stable identifier associated with this tray handle.
pub fn Tray::identifier(self : Tray) -> String {
  self.identifier
}

///|
/// Returns the platform reported when this tray handle was created.
pub fn Tray::platform(self : Tray) -> Platform {
  self.platform
}

///|
/// Returns the last icon path requested through `create()` or `set_icon()`.
pub fn Tray::icon(self : Tray) -> String? {
  self.icon
}

///|
/// Returns the last tooltip requested through `create()`, `show()`, or
/// `set_tooltip()`.
pub fn Tray::tooltip(self : Tray) -> String {
  self.tooltip
}

///|
/// Returns whether this tray handle is currently believed to be visible.
pub fn Tray::is_visible(self : Tray) -> Bool {
  self.visible
}

///|
/// Alias for `is_visible()`.
pub fn Tray::visible(self : Tray) -> Bool {
  self.visible
}

///|
/// Returns a clone of the last menu payload accepted by `set_menu()`.
pub fn Tray::menu_items(self : Tray) -> Array[TrayMenuItem] {
  clone_menu_items(self.menu)
}

///|
/// Shows the tray icon and optionally replaces the tooltip in the same call.
///
/// Passing `tooltip=Some(...)` is the most efficient way to update the tooltip
/// immediately before the tray becomes visible. The result reports the tray's
/// visible state after the call, and invoking this on a simulated test tray
/// updates only the MoonBit-side state.
///
/// Passing `tooltip=None` reuses the most recently stored tooltip. Successful
/// calls always resolve to `Ok(true)`. If the tray has already been destroyed,
/// or if the native backend rejects the operation, this returns `Err(message)`.
pub fn Tray::show(
  self : Tray,
  tooltip? : String? = None,
) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) => {
      let next_tooltip = tooltip.unwrap_or(self.tooltip)
      match validate_c_text("tooltip", next_tooltip) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      if !self.native {
        self.tooltip = next_tooltip
        self.visible = true
        Ok(true)
      } else if show_state_ffi(self.handle, encode_text(next_tooltip)) {
        self.tooltip = next_tooltip
        self.visible = true
        Ok(true)
      } else {
        Err(self.state_error(self.handle, "tray.show failed"))
      }
    }
  }
}

///|
/// Hides the tray icon while keeping the handle valid for later `show()` calls.
///
/// The returned boolean reflects the post-call visibility state, so successful
/// calls resolve to `Ok(false)` whether the tray is native or simulated.
///
/// This is safe to call even when the tray is already hidden; the handle stays
/// valid and can be shown again later. Destroyed trays still reject the call
/// with an error.
pub fn Tray::hide(self : Tray) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) =>
      if !self.native {
        self.visible = false
        Ok(false)
      } else if hide_state_ffi(self.handle) {
        self.visible = false
        Ok(false)
      } else {
        Err(self.state_error(self.handle, "tray.hide failed"))
      }
  }
}

///|
/// Replaces the current tooltip text without changing visibility.
///
/// Platforms that cannot show a real tooltip may map this value to the nearest
/// native concept available to the host desktop environment. The returned
/// boolean mirrors whether the tray is visible after the update.
///
/// Hidden trays keep the new tooltip so the next `show()` call reuses it by
/// default. Successful calls return the current visible state, while destroyed
/// trays or backend failures return `Err(message)`.
pub fn Tray::set_tooltip(self : Tray, tooltip : String) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) =>
      match validate_c_text("tooltip", tooltip) {
        Err(error) => Err(error)
        Ok(_) =>
          if !self.native {
            self.tooltip = tooltip
            Ok(self.visible)
          } else if set_tooltip_ffi(self.handle, encode_text(tooltip)) {
            self.tooltip = tooltip
            Ok(self.visible)
          } else {
            Err(self.state_error(self.handle, "tray.set_tooltip failed"))
          }
      }
  }
}

///|
/// Changes the tray icon path or resets it to the platform default when `None`
/// is passed.
///
/// This updates the stored icon preference even for simulated trays used in
/// tests, and the returned boolean mirrors whether the tray is visible after
/// the change.
///
/// Pass `Some(path)` to request a specific icon file, or `None` to fall back to
/// the backend's default tray icon. Successful calls return the current visible
/// state; destroyed trays and backend failures return `Err(message)`.
pub fn Tray::set_icon(self : Tray, icon : String?) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) =>
      match validate_optional_c_text("icon", icon) {
        Err(error) => Err(error)
        Ok(_) =>
          if !self.native {
            self.icon = icon
            Ok(self.visible)
          } else if set_icon_ffi(self.handle, encode_optional_text(icon)) {
            self.icon = icon
            Ok(self.visible)
          } else {
            Err(self.state_error(self.handle, "tray.set_icon failed"))
          }
      }
  }
}

///|
/// Replaces the context menu shown for this tray icon.
///
/// The menu supports `normal`, `separator`, `checkbox`, and nested `submenu`
/// items. Normal and checkbox items must have non-empty `id` and `label`
/// values; item ids must be unique across the whole menu tree so click events
/// can be routed reliably.
///
/// Successful calls return the current visible state. Unsupported operating
/// systems, missing native menu backends, or invalid menu payloads return
/// `Err(message)`.
pub fn Tray::set_menu(
  self : Tray,
  items : Array[TrayMenuItem],
) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) =>
      match validate_menu(items) {
        Err(error) => Err(error)
        Ok(_) => {
          let stored_items = clone_menu_items(items)
          if !self.native {
            self.menu = stored_items
            Ok(self.visible)
          } else if apply_menu_transaction(self.handle, items) {
            self.menu = stored_items
            Ok(self.visible)
          } else {
            Err(self.state_error(self.handle, "tray.set_menu failed"))
          }
        }
      }
  }
}

///|
/// Drains all currently queued tray events.
///
/// For native trays, this polls the backend event queue until it is empty. For
/// simulated trays used in tests, this returns and clears the MoonBit-side
/// event queue. Destroyed trays return an empty array.
pub fn Tray::drain_events(self : Tray) -> Array[TrayEvent] {
  if self.destroyed {
    return []
  }
  if !self.native {
    let drained = self.events
    self.events = []
    return drained
  }
  let drained : Array[TrayEvent] = []
  let mut polling = true
  while polling {
    match decode_bytes(poll_event_json_ffi(self.handle)) {
      Some(raw) =>
        match decode_event(raw) {
          Some(event) => drained.push(event)
          None => ()
        }
      None => polling = false
    }
  }
  drained
}

///|
/// Pumps one native tray loop iteration.
///
/// Call this from long-running native applications when the host platform needs
/// event-loop progress from the tray backend. A return value of `Ok(false)`
/// means the backend asked to stop processing. Simulated trays always return
/// `Ok(true)` so unit tests can exercise state transitions without a native
/// message loop.
///
/// Passing `blocking=true` lets the backend wait for work before returning;
/// `blocking=false` performs at most one non-blocking iteration. Backend errors
/// and calls on destroyed trays return `Err(message)`.
pub fn Tray::pump(
  self : Tray,
  blocking? : Bool = false,
) -> Result[Bool, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) =>
      if !self.native {
        Ok(true)
      } else {
        let status = pump_state_ffi(self.handle, if blocking { 1 } else { 0 })
        if status > 0 {
          Ok(true)
        } else if status == 0 {
          Ok(false)
        } else {
          Err(self.state_error(self.handle, "tray.pump failed"))
        }
      }
  }
}

///|
/// Releases the underlying native resources and turns the handle into a no-op
/// object that rejects later operations.
///
/// Calling `destroy()` more than once is safe; repeated calls are ignored after
/// the first teardown has marked the handle as destroyed.
///
/// After destruction the tray becomes permanently unusable: `show()`, `hide()`,
/// `set_tooltip()`, `set_icon()`, `set_menu()`, and `pump()` will all return
/// errors instead of touching the native backend again.
///
/// Native tray operations, including `destroy()`, must run on the thread that
/// called `create()`; macOS already required this, and it is now enforced on
/// all platforms.
pub fn Tray::destroy(self : Tray) -> Unit {
  if self.destroyed {
    return ()
  }
  if self.native {
    destroy_state_ffi(self.handle)
  }
  self.handle = zero_handle()
  self.native = false
  self.visible = false
  self.events = []
  self.destroyed = true
}

///|
/// Validates all menu items before state or native resources are changed.
fn validate_menu(items : Array[TrayMenuItem]) -> Result[Unit, String] {
  let seen_ids : Array[String] = []
  validate_menu_items(items, seen_ids, depth=0)
}

///|
/// Maximum submenu depth accepted by the native transaction builder.
fn max_menu_depth() -> Int {
  8
}

///|
/// Maximum UTF-8 bytes accepted for a clickable item id.
fn max_menu_item_id_bytes() -> Int {
  128
}

///|
/// Maximum clickable menu items addressable by native command ids.
fn max_menu_clickable_items() -> Int {
  64
}

///|
/// Validates a menu subtree and tracks clickable ids globally.
fn validate_menu_items(
  items : Array[TrayMenuItem],
  seen_ids : Array[String],
  depth~ : Int,
) -> Result[Unit, String] {
  if depth > max_menu_depth() {
    return Err("tray menu submenu depth exceeds 8")
  }
  for item in items {
    match item {
      Normal(id~, label~, ..) | Checkbox(id~, label~, ..) =>
        match validate_clickable_menu_item(id, label, seen_ids) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      Separator => ()
      Submenu(label~, items~, ..) => {
        if label.trim().to_owned().is_empty() {
          return Err("tray submenu label must not be empty")
        }
        if text_has_nul(label) {
          return Err("tray submenu label must not contain NUL bytes")
        }
        match validate_menu_items(items, seen_ids, depth=depth + 1) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
    }
  }
  Ok(())
}

///|
/// Validates a clickable menu item and records its id.
fn validate_clickable_menu_item(
  id : String,
  label : String,
  seen_ids : Array[String],
) -> Result[Unit, String] {
  let normalized_id = id.trim().to_owned()
  let normalized_label = label.trim().to_owned()
  if normalized_id.is_empty() {
    return Err("tray menu item id must not be empty")
  }
  if id != normalized_id {
    return Err("tray menu item id must not have leading or trailing whitespace")
  }
  if text_has_nul(id) {
    return Err("tray menu item id must not contain NUL bytes")
  }
  // encode_text appends a NUL terminator, so the encoded length is the C
  // strlen + 1; `>` keeps the exact 127-accept / 128-reject strlen boundary
  // required by the native side (strlen(id) < 128).
  if encode_text(id).length() > max_menu_item_id_bytes() {
    return Err("tray menu item id is too long")
  }
  if normalized_label.is_empty() {
    return Err("tray menu item label must not be empty")
  }
  if text_has_nul(normalized_label) {
    return Err("tray menu item label must not contain NUL bytes")
  }
  if seen_ids.contains(id) {
    return Err("tray menu item id must be unique: " + id)
  }
  if seen_ids.length() >= max_menu_clickable_items() {
    return Err("tray menu has too many clickable items")
  }
  seen_ids.push(id)
  Ok(())
}

///|
/// Rejects embedded NUL because native FFI strings are C strings.
fn validate_c_text(field : String, value : String) -> Result[Unit, String] {
  if text_has_nul(value) {
    Err("tray " + field + " must not contain NUL bytes")
  } else {
    Ok(())
  }
}

///|
/// Rejects embedded NUL in optional native FFI strings.
fn validate_optional_c_text(
  field : String,
  value : String?,
) -> Result[Unit, String] {
  match value {
    Some(text) => validate_c_text(field, text)
    None => Ok(())
  }
}

///|
/// Returns whether text contains an embedded C string terminator.
fn text_has_nul(value : String) -> Bool {
  for c in value {
    if c == '\u{0}' {
      return true
    }
  }
  false
}

///|
/// Clones menu items before storing caller-provided arrays in tray state.
fn clone_menu_items(items : Array[TrayMenuItem]) -> Array[TrayMenuItem] {
  let cloned : Array[TrayMenuItem] = []
  for item in items {
    cloned.push(
      match item {
        Normal(id~, label~, enabled~) => Normal(id~, label~, enabled~)
        Separator => Separator
        Checkbox(id~, label~, checked~, enabled~) =>
          Checkbox(id~, label~, checked~, enabled~)
        Submenu(label~, items~, enabled~) =>
          Submenu(label~, items=clone_menu_items(items), enabled~)
      },
    )
  }
  cloned
}

///|
/// Applies a native menu replacement transaction.
fn apply_menu_transaction(handle : Int64, items : Array[TrayMenuItem]) -> Bool {
  if !menu_begin_ffi(handle) {
    return false
  }
  if append_menu_items(handle, items) && menu_commit_ffi(handle) {
    true
  } else {
    menu_abort_ffi(handle)
    false
  }
}

///|
/// Appends a menu subtree to the active native transaction.
fn append_menu_items(handle : Int64, items : Array[TrayMenuItem]) -> Bool {
  for item in items {
    let ok = match item {
      Normal(id~, label~, enabled~) =>
        menu_add_normal_ffi(
          handle,
          encode_text(id),
          encode_text(label),
          bool_to_int(enabled),
        )
      Separator => menu_add_separator_ffi(handle)
      Checkbox(id~, label~, checked~, enabled~) =>
        menu_add_checkbox_ffi(
          handle,
          encode_text(id),
          encode_text(label),
          bool_to_int(enabled),
          bool_to_int(checked),
        )
      Submenu(label~, items~, enabled~) =>
        if menu_begin_submenu_ffi(
            handle,
            encode_text(label),
            bool_to_int(enabled),
          ) {
          if append_menu_items(handle, items) {
            menu_end_submenu_ffi(handle)
          } else {
            false
          }
        } else {
          false
        }
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// Converts a MoonBit boolean to the C ABI integer convention.
fn bool_to_int(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
/// Decodes one native tray event JSON payload.
fn decode_event(raw : String) -> TrayEvent? {
  try @json.parse(raw) catch {
    _ => None
  } noraise {
    json =>
      match json {
        { "type": "click", .. } => Some(Click)
        { "type": "rightClick", .. } => Some(RightClick)
        { "type": "doubleClick", .. } => Some(DoubleClick)
        { "type": "menuItemClick", "item_id": String(item_id), .. } =>
          Some(MenuItemClick(item_id))
        _ => None
      }
  }
}

///|
/// Rejects operations performed on a tray handle after it has been destroyed.
fn Tray::ensure_alive(self : Tray) -> Result[Unit, String] {
  if self.destroyed {
    Err("tray handle has been destroyed")
  } else {
    Ok(())
  }
}

///|
/// Decodes the last native state error or falls back to the provided message.
fn Tray::state_error(_self : Tray, handle : Int64, fallback : String) -> String {
  decode_bytes(last_state_error_ffi(handle)).unwrap_or(fallback)
}

///|
/// Encodes UTF-8 text as a NUL-terminated C string for the native backend.
fn encode_text(value : String) -> Bytes {
  @ffi.to_cstr(value)
}

///|
/// Encodes optional text as a NUL-terminated C string, empty for `None`.
fn encode_optional_text(value : String?) -> Bytes {
  @ffi.to_cstr(value.unwrap_or(""))
}

///|
/// Decodes non-empty UTF-8 byte payloads into strings.
fn decode_bytes(bytes : Bytes) -> String? {
  if bytes.is_empty() {
    None
  } else {
    Some(@utf8.decode_lossy(bytes))
  }
}

///|
/// Returns the sentinel handle value used for simulated or destroyed trays.
fn zero_handle() -> Int64 {
  Int64::from_int(0)
}
