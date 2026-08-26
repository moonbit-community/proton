///|
let get_idle_time_command = @power_monitor_contract.get_idle_time

///|
let get_power_source_command = @power_monitor_contract.get_power_source

///|
let active_monitor : Ref[@sys_power_monitor.PowerMonitor?] = Ref(None)

///|
let event_wakeup : Ref[@proton_extension.EventWakeup?] = Ref(None)

///|
fn ensure_monitor() -> @sys_power_monitor.PowerMonitor raise PowerMonitorError {
  match active_monitor.val {
    Some(monitor) => monitor
    None => {
      let monitor = @sys_power_monitor.PowerMonitor() catch {
        error => raise BackendUnavailable(detail=error.to_string())
      }
      match event_wakeup.val {
        Some(wakeup) => monitor.set_event_wakeup(wakeup)
        None => ()
      }
      // Best-effort: enable the event watch backend. A platform that cannot
      // watch only loses events; polling queries stay fully usable.
      monitor.start_watching() catch {
        _ => ()
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
  @power_monitor_contract.IdleTimeReply::{ idle_seconds: seconds, }
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
fn power_monitor_event(
  event : @sys_power_monitor.PowerMonitorEvent,
) -> @proton_extension.Event raise {
  let payload = @power_monitor_contract.PowerMonitorEventPayload::{ }
  match event {
    Suspend => @proton_extension.event(@power_monitor_contract.suspend, payload)
    Resume =>
      @proton_extension.event(@power_monitor_contract.resume_event, payload)
    OnAC => @proton_extension.event(@power_monitor_contract.on_ac, payload)
    OnBattery =>
      @proton_extension.event(@power_monitor_contract.on_battery, payload)
    LockScreen =>
      @proton_extension.event(@power_monitor_contract.lock_screen, payload)
    UnlockScreen =>
      @proton_extension.event(@power_monitor_contract.unlock_screen, payload)
  }
}

///|
fn start_event_source(wakeup : @proton_extension.EventWakeup) -> Unit {
  event_wakeup.val = Some(wakeup)
  match active_monitor.val {
    Some(monitor) => monitor.set_event_wakeup(wakeup)
    None => ignore(ensure_monitor()) catch { _ => () }
  }
}

///|
fn drain_events() -> Array[@proton_extension.Event] raise {
  match active_monitor.val {
    Some(monitor) => monitor.drain_events().map(power_monitor_event)
    None => []
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
  event_wakeup.val = None
}

///|
let extension_definition : @proton_extension.Extension = @proton_extension.typed(
  @power_monitor_contract.extension,
  generated_extension_command_routes(),
  fn(registrar) raise { register_commands(registrar) },
  event_source=@proton_extension.event_source(
    wakeup => start_event_source(wakeup),
    () => cleanup_power_monitor(),
    () => drain_events(),
  ),
)

///|
/// Grants power-monitor commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension_definition)
}
