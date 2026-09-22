///|
/// Process-wide application readiness, mirroring Electron's `app.isReady()`.
///
/// A process runs at most one Proton application, so readiness is process
/// state rather than a property of one runtime handle.
priv struct AppReadiness {
  mut ready : Bool
}

///|
let app_readiness : AppReadiness = { ready: false, }

///|
/// Reports whether this process finished Proton application startup.
///
/// Readiness becomes true once the configured `app_lifecycle` hooks completed
/// and the initial windows became ready, and returns to false when Proton
/// starts tearing the runtime down. Electron's `ready` event corresponds to
/// `App::app_lifecycle(on_start=...)`, which still observes `false`.
pub fn is_ready() -> Bool {
  app_readiness.ready
}

///|
fn AppReadiness::mark_ready(self : AppReadiness) -> Unit {
  self.ready = true
}

///|
fn AppReadiness::mark_not_ready(self : AppReadiness) -> Unit {
  self.ready = false
}

///|
/// Makes this application the active app.
///
/// This is Electron's `app.focus`. macOS activates the application and uses
/// `steal` for its option of the same name, which keeps another frontmost
/// application in place when it is `false`. Windows and Linux focus the
/// application's first visible window instead. Calling it while no window is
/// visible is a successful no-operation.
pub fn ApplicationContext::focus(
  self : ApplicationContext,
  steal? : Bool = false,
) -> Unit raise AppControlError {
  ignore(self)
  @native.app_focus(steal) catch {
    error => raise app_control_native_error("focusing the application", error)
  }
}

///|
/// Hides every application window without minimizing it.
///
/// This is Electron's macOS-only `app.hide`. Other platforms raise
/// `UnsupportedPlatform` instead of pretending that the application is hidden.
/// Use `show` to restore the windows.
pub fn ApplicationContext::hide(
  self : ApplicationContext,
) -> Unit raise AppControlError {
  ignore(self)
  @native.app_hide() catch {
    error => raise app_control_native_error("hiding the application", error)
  }
}

///|
/// Shows application windows after they were hidden.
///
/// This is Electron's macOS-only `app.show`. Other platforms raise
/// `UnsupportedPlatform`. The windows are restored without becoming the active
/// application; call `focus` when the application should also be activated.
pub fn ApplicationContext::show(
  self : ApplicationContext,
) -> Unit raise AppControlError {
  ignore(self)
  @native.app_show() catch {
    error => raise app_control_native_error("showing the application", error)
  }
}

///|
/// Reports whether the application is the active app.
///
/// This is Electron's macOS-only `app.isActive`. Other platforms raise
/// `UnsupportedPlatform` rather than reporting a value they cannot observe.
pub fn ApplicationContext::is_active(
  self : ApplicationContext,
) -> Bool raise AppControlError {
  ignore(self)
  @native.app_is_active() catch {
    error =>
      raise app_control_native_error(
        "reading the active application state", error,
      )
  }
}

///|
/// Reports whether the application and all of its windows are hidden.
///
/// This is Electron's macOS-only `app.isHidden`, the readback for `hide` and
/// `show`. Other platforms raise `UnsupportedPlatform`.
pub fn ApplicationContext::is_hidden(
  self : ApplicationContext,
) -> Bool raise AppControlError {
  ignore(self)
  @native.app_is_hidden() catch {
    error =>
      raise app_control_native_error(
        "reading the hidden application state", error,
      )
  }
}
