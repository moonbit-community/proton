///|
/// A rectangle in physical pixel coordinates with the top-left origin shared
/// across the facade.
pub struct Rect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Debug, Eq)

///|
pub extend Rect with Eq::{not_equal, equal}

///|
pub extend Rect with Debug::{to_repr}

///|
/// A display geometry snapshot mirroring Electron's `Display`.
pub struct DisplayInfo {
  id : Int
  bounds : Rect
  work_area : Rect
  scale_factor : Double
  is_primary : Bool
} derive(Debug, Eq)

///|
pub extend DisplayInfo with Eq::{not_equal, equal}

///|
pub extend DisplayInfo with Debug::{to_repr}

///|
/// A point in the root (physical pixel) coordinate space.
pub struct Point {
  x : Int
  y : Int
} derive(Debug, Eq)

///|
pub extend Point with Eq::{not_equal, equal}

///|
pub extend Point with Debug::{to_repr}

///|
/// Display topology events delivered by the watch backend, mirroring
/// Electron's `screen` module events.
pub enum ScreenMonitorEvent {
  DisplayAdded
  DisplayRemoved
  DisplayMetricsChanged
} derive(Debug, Eq)

///|
pub extend ScreenMonitorEvent with Eq::{not_equal, equal}

///|
pub extend ScreenMonitorEvent with Debug::{to_repr}

///|
pub struct ScreenMonitor {
  priv handle : State
}

///|
/// Wire shapes produced by the native backend's JSON payloads.
struct DisplaysWire {
  displays : Array[DisplayWire]
} derive(FromJson)

///|
pub extend DisplaysWire with @json.FromJson::{from_json}

///|
struct DisplayWire {
  id : Int
  x : Int
  y : Int
  width : Int
  height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  scale_factor_percent : Int
  is_primary : Bool
} derive(FromJson)

///|
pub extend DisplayWire with @json.FromJson::{from_json}

///|
struct PointWire {
  x : Int
  y : Int
} derive(FromJson)

///|
pub extend PointWire with @json.FromJson::{from_json}

///|
fn display_from_wire(w : DisplayWire) -> DisplayInfo {
  DisplayInfo::{
    id: w.id,
    bounds: Rect::{ x: w.x, y: w.y, width: w.width, height: w.height, },
    work_area: Rect::{
      x: w.work_x,
      y: w.work_y,
      width: w.work_width,
      height: w.work_height,
    },
    scale_factor: w.scale_factor_percent.to_double() / 100.0,
    is_primary: w.is_primary,
  }
}

///|
fn decode_displays(bytes : Bytes) -> DisplaysWire? {
  let text = @utf8.decode_lossy(bytes[:])
  if text.is_empty() {
    return None
  }
  let wire : DisplaysWire = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  Some(wire)
}

///|
fn decode_display(bytes : Bytes) -> DisplayWire? {
  let text = @utf8.decode_lossy(bytes[:])
  if text.is_empty() {
    return None
  }
  let wire : DisplayWire = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  Some(wire)
}

///|
fn decode_point(bytes : Bytes) -> PointWire? {
  let text = @utf8.decode_lossy(bytes[:])
  if text.is_empty() {
    return None
  }
  let wire : PointWire = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  Some(wire)
}

///|
fn decode_native_detail(bytes : Bytes) -> String {
  if bytes.is_empty() {
    return ""
  }
  @utf8.decode_lossy(bytes[:])
}

///|
/// Creates a new screen monitor handle. The native backend is verified during
/// creation so an unavailable platform surfaces immediately as
/// `BackendUnavailable`.
pub fn ScreenMonitor::new() -> ScreenMonitor raise ScreenMonitorError {
  let handle = native_create()
  let monitor = ScreenMonitor::{ handle, }
  let status = native_status(handle)
  if status != native_status_ok {
    raise monitor.classify_status(status, "create")
  }
  monitor
}

///|
fn ScreenMonitor::classify_status(
  self : ScreenMonitor,
  status : Int,
  operation : String,
) -> ScreenMonitorError {
  let detail = decode_native_detail(native_last_error(self.handle))
  match status {
    _ if status == native_status_backend_unavailable =>
      BackendUnavailable(detail~)
    _ if status == native_status_operation_failed =>
      OperationFailed(operation~, detail~)
    _ if status == native_status_empty => Empty
    _ => OperationFailed(operation~, detail~)
  }
}

///|
/// Returns every connected display, with the primary display listed first.
/// Corresponds to Electron's `screen.getAllDisplays()`.
pub fn ScreenMonitor::displays(
  self : ScreenMonitor,
) -> Array[DisplayInfo] raise ScreenMonitorError {
  let bytes = native_enumerate_json(self.handle)
  let status = native_status(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "displays")
  }
  match decode_displays(bytes) {
    Some(wire) => wire.displays.map(fn(d) { display_from_wire(d) })
    None => raise Empty
  }
}

///|
/// Returns the primary display. Corresponds to Electron's
/// `screen.getPrimaryDisplay()`; raises `Empty` when no display is connected.
pub fn ScreenMonitor::primary_display(
  self : ScreenMonitor,
) -> DisplayInfo raise ScreenMonitorError {
  let all = self.displays()
  for display in all {
    if display.is_primary {
      return display
    }
  }
  if all.is_empty() {
    raise Empty
  } else {
    all[0]
  }
}

///|
/// Returns the display that is nearest to the given point, preferring a display
/// that actually contains the point. Corresponds to Electron's
/// `screen.getDisplayNearestPoint(point)`.
pub fn ScreenMonitor::display_nearest_point(
  self : ScreenMonitor,
  x : Int,
  y : Int,
) -> DisplayInfo raise ScreenMonitorError {
  let bytes = native_nearest_display_json(self.handle, x, y)
  let status = native_status(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "display_nearest_point")
  }
  match decode_display(bytes) {
    Some(wire) => display_from_wire(wire)
    None => raise Empty
  }
}

///|
/// Returns the current cursor position in physical pixels with the top-left
/// origin. Corresponds to Electron's `screen.getCursorScreenPoint()`.
pub fn ScreenMonitor::cursor_point(
  self : ScreenMonitor,
) -> Point raise ScreenMonitorError {
  let bytes = native_cursor_point_json(self.handle)
  let status = native_status(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "cursor_point")
  }
  match decode_point(bytes) {
    Some(wire) => Point::{ x: wire.x, y: wire.y, }
    None => raise Empty
  }
}

///|
/// Starts the event watch backend. The backend is best-effort: a platform that
/// cannot watch (for example Linux without an X11 display or RandR) records the
/// failure on the native side and returns `BackendUnavailable`, leaving polling
/// queries fully usable.
pub fn ScreenMonitor::start_watching(
  self : ScreenMonitor,
) -> Unit raise ScreenMonitorError {
  let status = native_start_watching(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "start_watching")
  }
}

///|
/// Stops the event watch backend and joins its thread. Idempotent.
pub fn ScreenMonitor::stop_watching(
  self : ScreenMonitor,
) -> Unit raise ScreenMonitorError {
  let status = native_stop_watching(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "stop_watching")
  }
}

///|
/// Drains every pending event from the queue. Returns an empty array when no
/// event is pending; never raises for an empty queue.
pub fn ScreenMonitor::drain_events(
  self : ScreenMonitor,
) -> Array[ScreenMonitorEvent] {
  let events : Array[ScreenMonitorEvent] = []
  let event = Ref(0)
  while true {
    let status = native_take_event(self.handle, event)
    if status == native_status_ok {
      events.push(screen_monitor_event_from_native_code(event.val))
    } else {
      break
    }
  }
  events
}

///|
fn screen_monitor_event_from_native_code(code : Int) -> ScreenMonitorEvent {
  match code {
    _ if code == native_event_added => DisplayAdded
    _ if code == native_event_removed => DisplayRemoved
    _ if code == native_event_metrics_changed => DisplayMetricsChanged
    _ => DisplayMetricsChanged
  }
}

///|
/// Releases the native backend and tears the watch thread down. Idempotent.
pub fn ScreenMonitor::destroy(self : ScreenMonitor) -> Unit {
  native_destroy(self.handle)
}
