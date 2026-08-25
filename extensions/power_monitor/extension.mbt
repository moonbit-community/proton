///|
let get_idle_time_command = @power_monitor_contract.get_idle_time

///|
let get_power_source_command = @power_monitor_contract.get_power_source

///|
let drain_events_command = @power_monitor_contract.drain_events

///|
let active_monitor : Ref[@sys_power_monitor.PowerMonitor?] = Ref(None)

///|
fn ensure_monitor() -> @sys_power_monitor.PowerMonitor raise PowerMonitorError {
  match active_monitor.val {
    Some(monitor) => monitor
    None => {
      let monitor = @sys_power_monitor.PowerMonitor() catch {
        error => raise BackendUnavailable(detail=error.to_string())
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
async fn emit_power_monitor_event(
  context : @proton.CommandContext,
  event : @sys_power_monitor.PowerMonitorEvent,
) -> Unit {
  let payload = @power_monitor_contract.PowerMonitorEventPayload::{  }
  match event {
    Suspend => context.emit(@power_monitor_contract.suspend, payload)
    Resume => context.emit(@power_monitor_contract.resume_event, payload)
    OnAC => context.emit(@power_monitor_contract.on_ac, payload)
    OnBattery => context.emit(@power_monitor_contract.on_battery, payload)
    LockScreen => context.emit(@power_monitor_contract.lock_screen, payload)
    UnlockScreen => context.emit(@power_monitor_contract.unlock_screen, payload)
  }
}

///|
/// Drains native power-monitor events into JavaScript extension events.
#proton.command(contract=drain_events_command)
async fn drain_events(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @power_monitor_contract.PowerMonitorEventReply {
  let monitor = ensure_monitor()
  let events = monitor.drain_events()
  for event in events {
    emit_power_monitor_event(context, event)
  }
  @power_monitor_contract.PowerMonitorEventReply::{ count: events.length() }
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
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @power_monitor_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    scripts=[
      @proton_extension.poller_script(
        js_namespace="powerMonitor",
        drain_method="drainEvents",
        poller_field="__protonEventPoller",
      ),
    ],
    on_destroy=fn() { cleanup_power_monitor() },
  )
}

///|
/// Grants power-monitor commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
