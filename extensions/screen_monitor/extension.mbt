///|
let get_all_displays_command = @screen_monitor_contract.get_all_displays

///|
let get_primary_display_command = @screen_monitor_contract.get_primary_display

///|
let get_display_nearest_point_command = @screen_monitor_contract.get_display_nearest_point

///|
let get_cursor_point_command = @screen_monitor_contract.get_cursor_point

///|
let drain_events_command = @screen_monitor_contract.drain_events

///|
let active_monitor : Ref[@sys_screen_monitor.ScreenMonitor?] = Ref(None)

///|
fn ensure_monitor() -> @sys_screen_monitor.ScreenMonitor raise ScreenMonitorError {
  match active_monitor.val {
    Some(monitor) => monitor
    None => {
      let monitor = @sys_screen_monitor.ScreenMonitor::new() catch {
        error => raise BackendUnavailable(detail=error.to_string())
      }
      // Best-effort: enable the event watch backend. A platform that cannot
      // watch only loses topology events; polling queries stay fully usable.
      monitor.start_watching() catch {
        _ => ()
      }
      active_monitor.val = Some(monitor)
      monitor
    }
  }
}

///|
fn display_to_contract(
  d : @sys_screen_monitor.DisplayInfo,
) -> @screen_monitor_contract.DisplayJSON {
  @screen_monitor_contract.DisplayJSON::{
    id: d.id,
    bounds: @screen_monitor_contract.DisplayBounds::{
      x: d.bounds.x,
      y: d.bounds.y,
      width: d.bounds.width,
      height: d.bounds.height,
    },
    work_area: @screen_monitor_contract.DisplayBounds::{
      x: d.work_area.x,
      y: d.work_area.y,
      width: d.work_area.width,
      height: d.work_area.height,
    },
    scale_factor: d.scale_factor,
    is_primary: d.is_primary,
  }
}

///|
/// Emits an `activity` event describing which screen query command ran. Query
/// handlers call this so the renderer can observe screen API usage, matching
/// the activity convention shared across `proton_ext`.
async fn emit_activity(
  context : @proton.CommandContext,
  operation : String,
) -> Unit {
  context.emit(@screen_monitor_contract.activity, @screen_monitor_contract.ScreenMonitorActivity::{
    operation,
  })
}

///|
/// Returns every connected display with the primary display listed first.
/// Mirrors Electron's `screen.getAllDisplays()`.
#proton.command(contract=get_all_displays_command)
async fn get_all_displays(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @screen_monitor_contract.DisplaysReply {
  let monitor = ensure_monitor()
  let displays = monitor.displays() catch {
    error => raise QueryFailed(operation="displays", detail=error.to_string())
  }
  emit_activity(context, "getAllDisplays")
  @screen_monitor_contract.DisplaysReply::{
    displays: displays.map(fn(d) { display_to_contract(d) }),
  }
}

///|
/// Returns the primary display. Mirrors Electron's `screen.getPrimaryDisplay()`.
#proton.command(contract=get_primary_display_command)
async fn get_primary_display(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @screen_monitor_contract.DisplayReply {
  let monitor = ensure_monitor()
  let display = monitor.primary_display() catch {
    error =>
      raise QueryFailed(operation="primary_display", detail=error.to_string())
  }
  emit_activity(context, "getPrimaryDisplay")
  @screen_monitor_contract.DisplayReply::{
    display: display_to_contract(display),
  }
}

///|
/// Returns the display nearest to the given root point. Mirrors Electron's
/// `screen.getDisplayNearestPoint(point)`.
#proton.command(contract=get_display_nearest_point_command)
async fn get_display_nearest_point(
  context : @proton.CommandContext,
  request : @screen_monitor_contract.NearestPointRequest,
) -> @screen_monitor_contract.DisplayReply {
  let monitor = ensure_monitor()
  let display = monitor.display_nearest_point(request.x, request.y) catch {
    error =>
      raise QueryFailed(
        operation="display_nearest_point",
        detail=error.to_string(),
      )
  }
  emit_activity(context, "getDisplayNearestPoint")
  @screen_monitor_contract.DisplayReply::{
    display: display_to_contract(display),
  }
}

///|
/// Returns the current cursor position in physical pixels with a top-left
/// origin. Mirrors Electron's `screen.getCursorScreenPoint()`.
#proton.command(contract=get_cursor_point_command)
async fn get_cursor_point(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @screen_monitor_contract.CursorPointReply {
  let monitor = ensure_monitor()
  let point = monitor.cursor_point() catch {
    error =>
      raise QueryFailed(operation="cursor_point", detail=error.to_string())
  }
  emit_activity(context, "getCursorScreenPoint")
  @screen_monitor_contract.CursorPointReply::{
    point: @screen_monitor_contract.PointJSON::{ x: point.x, y: point.y, },
  }
}

///|
async fn emit_screen_event(
  context : @proton.CommandContext,
  event : @sys_screen_monitor.ScreenMonitorEvent,
  payload : @screen_monitor_contract.DisplayJSON,
) -> Unit {
  match event {
    DisplayAdded =>
      context.emit(@screen_monitor_contract.display_added, payload)
    DisplayRemoved =>
      context.emit(@screen_monitor_contract.display_removed, payload)
    DisplayMetricsChanged =>
      context.emit(@screen_monitor_contract.display_metrics_changed, payload)
  }
}

///|
/// Drains native display topology events and forwards each as a JavaScript
/// extension event carrying the current primary display snapshot.
#proton.command(contract=drain_events_command)
async fn drain_events(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @screen_monitor_contract.ScreenEventReply {
  let monitor = ensure_monitor()
  let events = monitor.drain_events()
  let payload = Some(display_to_contract(monitor.primary_display())) catch {
    _ => None
  }
  for event in events {
    match payload {
      Some(payload) => emit_screen_event(context, event, payload)
      None => ()
    }
  }
  @screen_monitor_contract.ScreenEventReply::{ count: events.length(), }
}

///|
fn cleanup_screen_monitor() -> Unit {
  match active_monitor.val {
    Some(monitor) => {
      monitor.destroy()
      active_monitor.val = None
    }
    None => ()
  }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @screen_monitor_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    scripts=[
      @proton_extension.poller_script(
        js_namespace="screen",
        drain_method="drainEvents",
        poller_field="__protonEventPoller",
      ),
    ],
    on_destroy=fn() { cleanup_screen_monitor() },
  )
}

///|
/// Grants screen-monitor commands to renderer targets selected by
/// `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
