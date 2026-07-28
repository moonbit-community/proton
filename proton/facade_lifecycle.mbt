///|
fn AppLifecycle::new() -> AppLifecycle {
  AppLifecycle::{ state: Constructing, window_state: NotCreated }
}

///|
fn AppLifecycle::begin_starting(self : AppLifecycle) -> Unit {
  match self.state {
    Constructing => self.state = Starting
    _ => abort("invalid application lifecycle transition to Starting")
  }
}

///|
fn AppLifecycle::begin_window_create(self : AppLifecycle) -> Unit {
  match self.window_state {
    NotCreated => self.window_state = Creating
    _ => abort("invalid window lifecycle transition to Creating")
  }
}

///|
fn AppLifecycle::finish_window_create(self : AppLifecycle) -> Unit {
  match self.window_state {
    Creating => self.window_state = Live
    _ => abort("invalid window lifecycle transition to Live")
  }
}

///|
fn AppLifecycle::begin_running(self : AppLifecycle) -> Unit {
  match (self.state, self.window_state) {
    (Starting, Live) => self.state = Running
    _ => abort("invalid application lifecycle transition to Running")
  }
}

///|
fn AppLifecycle::observe_window_closed(self : AppLifecycle) -> Unit {
  match self.window_state {
    Live | CloseRequested => self.window_state = VisiblyClosed
    VisiblyClosed | Destroying | Destroyed => ()
    NotCreated | Creating =>
      abort("window closed before native creation completed")
  }
  self.begin_closing()
}

///|
fn AppLifecycle::begin_closing(self : AppLifecycle) -> Unit {
  match self.state {
    Constructing | Starting | Running => self.state = Closing
    Closing | Draining | Destroying | Closed => ()
  }
  match self.window_state {
    Live => self.window_state = CloseRequested
    _ => ()
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
  match self.window_state {
    NotCreated | Creating => self.window_state = Destroyed
    Live | CloseRequested | VisiblyClosed => self.window_state = Destroying
    Destroying | Destroyed => ()
  }
}

///|
fn AppLifecycle::finish_window_destroy(self : AppLifecycle) -> Unit {
  match self.window_state {
    Destroying | Destroyed => self.window_state = Destroyed
    _ => abort("invalid window lifecycle transition to Destroyed")
  }
}

///|
fn AppLifecycle::finish(self : AppLifecycle) -> Unit {
  match self.state {
    Destroying => {
      self.window_state = Destroyed
      self.state = Closed
    }
    Closed => ()
    _ => abort("invalid application lifecycle transition to Closed")
  }
}

///|
fn app_cleanup(
  lifecycle : AppLifecycle,
  runtime : @native.Runtime,
  window : @native.Window?,
  command_host : CommandHostRuntime?,
  lifecycle_failures? : Array[AppCleanupError] = [],
) -> Array[AppCleanupError] {
  lifecycle.begin_draining()
  let failures = lifecycle_failures.copy()
  for error in close_command_host(command_host) {
    failures.push(CommandExtension(error))
  }
  lifecycle.begin_destroying()
  match window {
    Some(window) => {
      let failure_count = failures.length()
      window.destroy() catch {
        error => failures.push(WindowDestroy(error))
      }
      if failures.length() == failure_count {
        lifecycle.finish_window_destroy()
      }
    }
    None => lifecycle.finish_window_destroy()
  }
  let failure_count = failures.length()
  runtime.destroy() catch {
    error => failures.push(RuntimeDestroy(error))
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
