///|
pub(all) enum PowerSource {
  Unknown
  AC
  Battery
} derive(Debug, Eq)

///|
pub(all) struct PowerSourceInfo {
  source : PowerSource
  battery_percent : Int?
} derive(Debug, Eq)

///|
pub struct PowerMonitor {
  priv handle : State
}

///|
pub fn PowerMonitor::new() -> PowerMonitor raise PowerMonitorError {
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
