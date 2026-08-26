///|
pub(all) enum PowerSource {
  Unknown
  AC
  Battery
} derive(Debug, Eq)

///|
pub extend PowerSource with Eq::{not_equal, equal}

///|
pub extend PowerSource with Debug::{to_repr}

///|
pub(all) struct PowerSourceInfo {
  source : PowerSource
  battery_percent : Int?
} derive(Debug, Eq)

///|
pub extend PowerSourceInfo with Eq::{not_equal, equal}

///|
pub extend PowerSourceInfo with Debug::{to_repr}

///|
/// System power and session events delivered by the watch backend.
pub enum PowerMonitorEvent {
  Suspend
  Resume
  OnAC
  OnBattery
  LockScreen
  UnlockScreen
} derive(Debug, Eq)

///|
pub extend PowerMonitorEvent with Eq::{not_equal, equal}

///|
pub extend PowerMonitorEvent with Debug::{to_repr}

///|
pub struct PowerMonitor {
  priv handle : State
}

///|
pub fn PowerMonitor::PowerMonitor() -> PowerMonitor raise PowerMonitorError {
  let handle = native_create()
  let monitor = PowerMonitor::{ handle, }
  monitor.finish_create()
  monitor
}

///|
fn PowerMonitor::finish_create(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  let status = native_status(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "create")
  }
}

///|
pub fn PowerMonitor::idle_seconds(
  self : PowerMonitor,
) -> Int raise PowerMonitorError {
  let seconds : Ref[Int64] = Ref(0L)
  let status = native_idle_seconds(self.handle, seconds)
  if status != native_status_ok {
    raise self.classify_status(status, "idle_seconds")
  }
  Int64::to_int(seconds.val)
}

///|
pub fn PowerMonitor::power_source(
  self : PowerMonitor,
) -> PowerSourceInfo raise PowerMonitorError {
  let source_code = Ref(0)
  let percent = Ref(0)
  let has_percent = Ref(0)
  let status = native_source(self.handle, source_code, percent, has_percent)
  if status != native_status_ok {
    raise self.classify_status(status, "power_source")
  }
  PowerSourceInfo::{
    source: power_source_from_native_code(source_code.val),
    battery_percent: if has_percent.val != 0 {
      Some(percent.val)
    } else {
      None
    },
  }
}

///|
/// Starts the event watch backend. The backend is best-effort: a platform that
/// cannot watch (for example Linux without a system D-Bus) records the failure
/// on the native side and returns `BackendUnavailable`, leaving polling queries
/// fully usable.
pub fn PowerMonitor::start_watching(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  let status = native_start_watching(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "start_watching")
  }
}

///|
/// Stops the event watch backend and joins its thread. Idempotent.
pub fn PowerMonitor::stop_watching(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  let status = native_stop_watching(self.handle)
  if status != native_status_ok {
    raise self.classify_status(status, "stop_watching")
  }
}

///|
/// Drains every pending event from the queue. Returns an empty array when no
/// event is pending; never raises for an empty queue.
pub fn PowerMonitor::drain_events(
  self : PowerMonitor,
) -> Array[PowerMonitorEvent] {
  let events : Array[PowerMonitorEvent] = []
  let event = Ref(0)
  while true {
    let status = native_take_event(self.handle, event)
    if status == native_status_ok {
      events.push(power_monitor_event_from_native_code(event.val))
    } else {
      break
    }
  }
  events
}

///|
/// Installs the opaque native wakeup supplied by an embedding event loop.
#doc(hidden)
pub fn PowerMonitor::set_event_wakeup(
  self : PowerMonitor,
  wakeup : @ffi.EventWakeup,
) -> Unit {
  native_set_event_wakeup(self.handle, wakeup)
}

///|
fn PowerMonitor::classify_status(
  self : PowerMonitor,
  status : Int,
  operation : String,
) -> PowerMonitorError {
  let detail = decode_native_detail(native_last_error(self.handle))
  match status {
    _ if status == native_status_backend_unavailable =>
      BackendUnavailable(detail~)
    _ if status == native_status_operation_failed =>
      OperationFailed(operation~, detail~)
    _ => OperationFailed(operation~, detail~)
  }
}

///|
fn power_source_from_native_code(code : Int) -> PowerSource {
  match code {
    _ if code == native_source_ac => AC
    _ if code == native_source_battery => Battery
    _ if code == native_source_unknown => Unknown
    _ => Unknown
  }
}

///|
fn power_monitor_event_from_native_code(code : Int) -> PowerMonitorEvent {
  match code {
    _ if code == native_event_suspend => Suspend
    _ if code == native_event_resume => Resume
    _ if code == native_event_on_ac => OnAC
    _ if code == native_event_on_battery => OnBattery
    _ if code == native_event_lock_screen => LockScreen
    _ if code == native_event_unlock_screen => UnlockScreen
    _ => Suspend
  }
}

///|
fn decode_native_detail(bytes : Bytes) -> String {
  if bytes.is_empty() {
    return ""
  }
  @utf8.decode_lossy(bytes)
}

///|
pub fn PowerMonitor::destroy(self : PowerMonitor) -> Unit {
  native_destroy(self.handle)
}
