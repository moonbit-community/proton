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
  battery_percent : Int32?
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
  priv lifecycle : @async.Mutex
  priv mut completion : @pipe.PipeRead?
}

///|
pub fn PowerMonitor::PowerMonitor() -> PowerMonitor raise PowerMonitorError {
  let handle = native_create()
  let monitor = PowerMonitor::{
    handle,
    lifecycle: @async.Mutex(),
    completion: None,
  }
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
) -> Int32 raise PowerMonitorError {
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
/// fully usable. Linux startup waits asynchronously for registration. Cancelling
/// it waits for native cleanup before propagating cancellation.
pub async fn PowerMonitor::start_watching(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  self.lifecycle.acquire()
  defer self.lifecycle.release()
  if !(@async.platform is Linux) {
    let status = native_start_watching(self.handle, -1)
    if status != native_status_ok {
      raise self.classify_status(status, "start_watching")
    }
    return
  }
  if self.completion is Some(_) {
    let status = native_watch_status(self.handle)
    if status == native_status_ok {
      return
    }
    self.finish_stop()
  }
  let (reader, writer) = @pipe.pipe() catch {
    error =>
      raise OperationFailed(
        operation="start_watching",
        detail=error.to_string(),
      )
  }
  let status = native_start_watching(self.handle, writer.fd())
  writer.close()
  if status != native_status_ok {
    reader.close()
    raise self.classify_status(status, "start_watching")
  }
  self.completion = Some(reader)
  let mut started = false
  defer (async fn() -> Unit raise PowerMonitorError + nocancel {
    if !started {
      self.finish_stop()
    }
  })()
  let ready = reader.read_some(max_len=1) catch {
    error =>
      raise OperationFailed(
        operation="start_watching",
        detail=error.to_string(),
      )
  }
  let status = native_watch_status(self.handle)
  if ready is None || status != native_status_ok {
    raise self.classify_status(status, "start_watching")
  }
  started = true
}

///|
async fn PowerMonitor::finish_stop(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError + nocancel {
  ignore(native_stop_watching(self.handle))
  if self.completion is Some(reader) {
    defer {
      reader.close()
      self.completion = None
    }
    ignore(@async.protect_from_cancel(() => reader.read_all())) catch {
      error =>
        raise OperationFailed(
          operation="stop_watching",
          detail=error.to_string(),
        )
    }
  }
}

///|
/// Stops watching and asynchronously waits for native cleanup. Idempotent.
/// A concurrent startup is interrupted before waiting for its cleanup.
pub async fn PowerMonitor::stop_watching(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  ignore(native_stop_watching(self.handle))
  self.lifecycle.acquire()
  defer self.lifecycle.release()
  self.finish_stop()
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
  status : Int32,
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
fn power_source_from_native_code(code : Int32) -> PowerSource {
  match code {
    _ if code == native_source_ac => AC
    _ if code == native_source_battery => Battery
    _ if code == native_source_unknown => Unknown
    _ => Unknown
  }
}

///|
fn power_monitor_event_from_native_code(code : Int32) -> PowerMonitorEvent {
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
/// Stops watching, waits for cleanup, and releases native resources. Idempotent.
pub async fn PowerMonitor::destroy(
  self : PowerMonitor,
) -> Unit raise PowerMonitorError {
  self.stop_watching()
  native_destroy(self.handle)
}

///|
/// Removes the embedding loop wakeup and waits for any in-flight notification.
#doc(hidden)
pub fn PowerMonitor::clear_event_wakeup(self : PowerMonitor) -> Unit {
  native_clear_event_wakeup(self.handle)
}
