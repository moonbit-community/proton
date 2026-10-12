///|
/// Controls how the Dock tile requests attention, mirroring Electron's
/// `app.dock.bounce` argument.
pub(all) enum DockBounceType {
  /// Bounces the Dock tile once. The tile does not bounce when the application
  /// is already focused.
  Informational
  /// Bounces the Dock tile repeatedly until the application becomes active.
  Critical
} derive(Debug, Eq)

///|
pub extend DockBounceType with Eq::{not_equal, equal}

///|
pub extend DockBounceType with Debug::{to_repr}

///|
fn DockBounceType::native_value(self : DockBounceType) -> Int {
  match self {
    Informational => 0
    Critical => 1
  }
}

///|
/// Sets the application badge count, mirroring Electron's `app.setBadgeCount`.
///
/// macOS shows the count on the Dock tile and returns `true`. Windows and
/// Linux apply no badge and return `false`, matching Electron's Boolean result
/// instead of raising `UnsupportedPlatform`. Zero clears the badge. A negative
/// count is rejected.
pub fn ApplicationContext::set_badge_count(
  self : ApplicationContext,
  count : Int,
) -> Bool raise AppControlError {
  ignore(self)
  @native.app_set_badge_count(count) catch {
    error =>
      raise app_control_native_error(
        "setting the application badge count", error,
      )
  }
}

///|
/// Reads back the badge count set through `set_badge_count`, mirroring
/// Electron's `app.getBadgeCount`. Platforms without badge support report
/// zero.
pub fn ApplicationContext::badge_count(
  self : ApplicationContext,
) -> Int raise AppControlError {
  ignore(self)
  @native.app_badge_count() catch {
    error =>
      raise app_control_native_error(
        "reading the application badge count", error,
      )
  }
}

///|
/// Requests a bouncing Dock tile, mirroring Electron's `app.dock.bounce`.
///
/// macOS is the only platform with the AppKit operation; others raise
/// `UnsupportedPlatform`. The returned request id cancels the bounce through
/// `dock_cancel_bounce`. AppKit ignores the request while the application is
/// already focused.
pub fn ApplicationContext::dock_bounce(
  self : ApplicationContext,
  kind? : DockBounceType = Informational,
) -> Int raise AppControlError {
  ignore(self)
  @native.app_dock_bounce(kind.native_value()) catch {
    error => raise app_control_native_error("bouncing the Dock tile", error)
  }
}

///|
/// Cancels a bouncing Dock tile requested through `dock_bounce`, mirroring
/// Electron's `app.dock.cancelBounce`. Any platform without Dock support
/// raises `UnsupportedPlatform`.
pub fn ApplicationContext::dock_cancel_bounce(
  self : ApplicationContext,
  request_id : Int,
) -> Unit raise AppControlError {
  ignore(self)
  @native.app_dock_cancel_bounce(request_id) catch {
    error => raise app_control_native_error("cancelling the Dock bounce", error)
  }
}

///|
/// Sets the Dock badge text, mirroring Electron's `app.dock.setBadge`.
///
/// macOS is the only platform with the AppKit operation; others raise
/// `UnsupportedPlatform`. An empty string clears the badge.
pub fn ApplicationContext::dock_set_badge(
  self : ApplicationContext,
  text : String,
) -> Unit raise AppControlError {
  ignore(self)
  @native.app_dock_set_badge(text) catch {
    error => raise app_control_native_error("setting the dock badge", error)
  }
}

///|
/// Reads back the Dock badge text set through `dock_set_badge`, mirroring
/// Electron's `app.dock.getBadge`. Any platform without Dock support raises
/// `UnsupportedPlatform`.
pub fn ApplicationContext::dock_badge(
  self : ApplicationContext,
) -> String raise AppControlError {
  ignore(self)
  @native.app_dock_badge() catch {
    error => raise app_control_native_error("reading the dock badge", error)
  }
}
