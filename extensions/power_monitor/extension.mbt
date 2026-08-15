///|
let get_idle_time_command = @power_monitor_contract.get_idle_time

///|
let get_power_source_command = @power_monitor_contract.get_power_source

///|
let active_monitor : Ref[@sys_power_monitor.PowerMonitor?] = Ref(None)

///|
fn ensure_monitor() -> @sys_power_monitor.PowerMonitor raise PowerMonitorError {
  match active_monitor.val {
    Some(monitor) => monitor
    None => {
      let monitor = @sys_power_monitor.PowerMonitor::new() catch {
        error => raise BackendUnavailable(detail=error.to_string())
      }
      active_monitor.val = Some(monitor)
      monitor
    }
  }
}

///|
/// Queries the system idle time in seconds.
#proton.command(contract=get_idle_time_command)
async fn get_idle_time(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @power_monitor_contract.IdleTimeReply {
  let monitor = ensure_monitor()
  let seconds = monitor.idle_seconds() catch {
    error =>
      raise QueryFailed(operation="idle_seconds", detail=error.to_string())
  }
  context.emit(@power_monitor_contract.activity, @power_monitor_contract.PowerMonitorActivity::{
    operation: "get_idle_time",
  })
  @power_monitor_contract.IdleTimeReply::{ idle_seconds: seconds }
}

///|
/// Queries the current power source and battery level.
#proton.command(contract=get_power_source_command)
async fn get_power_source(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @power_monitor_contract.PowerSourceReply {
  let monitor = ensure_monitor()
  let info = monitor.power_source() catch {
    error =>
      raise QueryFailed(operation="power_source", detail=error.to_string())
  }
  context.emit(@power_monitor_contract.activity, @power_monitor_contract.PowerMonitorActivity::{
    operation: "get_power_source",
  })
  let source_name = match info.source {
    AC => "ac"
    Battery => "battery"
    Unknown => "unknown"
  }
  @power_monitor_contract.PowerSourceReply::{
    source: source_name,
    battery_percent: info.battery_percent,
  }
}

///|
fn cleanup_power_monitor() -> Unit {
  match active_monitor.val {
    Some(monitor) => {
      monitor.destroy()
      active_monitor.val = None
    }
    None => ()
  }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @power_monitor_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() { cleanup_power_monitor() },
  )
}
