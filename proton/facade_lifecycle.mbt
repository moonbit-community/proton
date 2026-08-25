///|
fn AppLifecycle::AppLifecycle() -> AppLifecycle {
  AppLifecycle::{ state: Constructing, }
}

///|
fn AppLifecycle::begin_starting(self : AppLifecycle) -> Unit {
  match self.state {
    Constructing => self.state = Starting
    _ => abort("invalid application lifecycle transition to Starting")
  }
}

///|
fn AppLifecycle::begin_running(self : AppLifecycle) -> Unit {
  match self.state {
    Starting => self.state = Running
    _ => abort("invalid application lifecycle transition to Running")
  }
}

///|
fn AppLifecycle::has_reached_running(self : AppLifecycle) -> Bool {
  match self.state {
    Running | Closing | Draining | Destroying | Closed => true
    Constructing | Starting => false
  }
}

///|
fn AppLifecycle::observe_window_closed(self : AppLifecycle) -> Unit {
  self.begin_closing()
}

///|
fn AppLifecycle::begin_closing(self : AppLifecycle) -> Unit {
  match self.state {
    Constructing | Starting | Running => self.state = Closing
    Closing | Draining | Destroying | Closed => ()
  }
}

///|
fn AppLifecycle::begin_draining(self : AppLifecycle) -> Unit {
  self.begin_closing()
  match self.state {
    Closing => self.state = Draining
    Draining | Destroying | Closed => ()
    _ => abort("invalid application lifecycle transition to Draining")
  }
}

///|
fn AppLifecycle::begin_destroying(self : AppLifecycle) -> Unit {
  self.begin_draining()
  match self.state {
    Draining => self.state = Destroying
    Destroying | Closed => ()
    _ => abort("invalid application lifecycle transition to Destroying")
  }
}

///|
fn AppLifecycle::finish(self : AppLifecycle) -> Unit {
  match self.state {
    Destroying => self.state = Closed
    Closed => ()
    _ => abort("invalid application lifecycle transition to Closed")
  }
}

///|
fn app_cleanup(
  lifecycle : AppLifecycle,
  runtime : @native.Runtime,
  windows : Array[RunningWindow],
  command_host : CommandHostRuntime?,
  lifecycle_failures? : Array[AppCleanupError] = [],
) -> Array[AppCleanupError] {
  lifecycle.begin_draining()
  let failures = lifecycle_failures.copy()
  for error in close_command_host(command_host) {
    failures.push(CommandExtension(error))
  }
  lifecycle.begin_destroying()
  for running in windows {
    running.window.destroy() catch {
      error =>
        failures.push(
          WindowDestroy(status=error.status(), detail=error.message()),
        )
    }
  }
  let failure_count = failures.length()
  runtime.destroy() catch {
    error =>
      failures.push(
        RuntimeDestroy(status=error.status(), detail=error.message()),
      )
  }
  if failures.length() == failure_count {
    lifecycle.finish()
  }
  failures
}

///|
fn cleanup_run_error(
  primary : AppRunError?,
  failures : Array[AppCleanupError],
) -> AppRunError? {
  if failures.length() == 0 {
    return primary
  }
  Some(
    CleanupFailed(
      primary=match primary {
        Some(error) => Some(error.message())
        None => None
      },
      failures~,
    ),
  )
}
