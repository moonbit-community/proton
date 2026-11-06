///|
/// Geometry and scaling information for the monitor containing a window.
#derive(Debug, Eq)
pub(all) struct WindowMonitor {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  work_x : Int32
  work_y : Int32
  work_width : Int32
  work_height : Int32
  scale_factor_percent : Int32
}

///|
pub extend WindowMonitor with Eq::{not_equal, equal}

///|
pub extend WindowMonitor with Debug::{to_repr}

///|
/// Describes the effective native window chrome theme.
#derive(Debug, Eq)
pub(all) enum WindowTheme {
  Light
  Dark
}

///|
pub extend WindowTheme with Eq::{not_equal, equal}

///|
pub extend WindowTheme with Debug::{to_repr}

///|
/// A point-in-time snapshot of a native window.
///
/// `theme` is the effective `Light` or `Dark` theme after resolving the
/// window's configured `WindowThemePreference`.
#derive(Debug, Eq)
pub(all) struct WindowState {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  monitor : WindowMonitor
  zoom_percent : Int32
  visible : Bool
  focused : Bool
  minimized : Bool
  maximized : Bool
  fullscreen : Bool
  always_on_top : Bool
  theme : WindowTheme
}

///|
pub extend WindowState with Eq::{not_equal, equal}

///|
pub extend WindowState with Debug::{to_repr}

///|
/// A point-in-time snapshot of a window's main browser page.
#derive(Debug, Eq)
pub(all) struct BrowserState {
  url : String
  title : String
  is_loading : Bool
  can_go_back : Bool
  can_go_forward : Bool
}

///|
pub extend BrowserState with Eq::{not_equal, equal}

///|
pub extend BrowserState with Debug::{to_repr}

///|
/// Information about one connected display.
#derive(Debug, Eq)
pub(all) struct ScreenInfo {
  id : Int32
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  work_x : Int32
  work_y : Int32
  work_width : Int32
  work_height : Int32
  scale_factor_percent : Int32
  is_primary : Bool
}

///|
pub extend ScreenInfo with Eq::{not_equal, equal}

///|
pub extend ScreenInfo with Debug::{to_repr}

///|
/// A point-in-time web contents view state snapshot.
#derive(Debug, Eq)
pub(all) struct ViewState {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  visible : Bool
  z_order : Int32
}

///|
pub extend ViewState with Eq::{not_equal, equal}

///|
pub extend ViewState with Debug::{to_repr}

///|
/// Structured information about a bridge bootstrap or runtime failure.
#derive(Debug, Eq)
pub(all) struct BridgeDiagnostic {
  stage : String
  code : String
  message : String
  page_instance : String
  url : String
  owner : String?
  source_url : String?
  source_line : String?
  line : Int32?
  column : Int32?
  stack : String?
  additional_failure_count : Int32?
  details_truncated : Bool
}

///|
pub extend BridgeDiagnostic with Eq::{not_equal, equal}

///|
pub extend BridgeDiagnostic with Debug::{to_repr}

///|
/// One update from an active page search. The selection rectangle uses the
/// target web contents coordinate space.
#derive(Debug, Eq)
pub(all) struct FindInPageResult {
  request_id : Int32
  active_match_ordinal : Int32
  matches : Int32
  selection_x : Int32
  selection_y : Int32
  selection_width : Int32
  selection_height : Int32
  final_update : Bool
}

///|
pub extend FindInPageResult with Eq::{not_equal, equal}

///|
pub extend FindInPageResult with Debug::{to_repr}

///|
/// The kind of browser task represented by a metric.
#derive(Debug, Eq)
pub(all) enum AppTaskType {
  Unknown
  /// The application's own browser process.
  Browser
  /// Chromium's GPU process, when it runs separately.
  Gpu
  Zygote
  Utility
  /// A page renderer task.
  Renderer
  Extension
  Guest
  Plugin
  SandboxHelper
  /// A dedicated, shared, or service worker task.
  Worker
}

///|
pub extend AppTaskType with Eq::{not_equal, equal}

///|
pub extend AppTaskType with Debug::{to_repr}

///|
/// A browser task and the resource usage of its hosting process.
///
/// Multiple tasks can share a process and repeat its full CPU and memory
/// usage. These values are not per-task usage and must not be summed across
/// records. The task ID is not a PID; no process grouping key is available.
#derive(Debug, Eq)
pub(all) struct AppTaskMetric {
  /// CEF's task identifier, stable for the lifetime of the task; not a PID.
  task_id : Int64
  task_type : AppTaskType
  /// Full CPU usage of the hosting process since the previous sample.
  /// 100% is one fully used core; zero until a sampling interval has passed.
  /// Shared-process tasks repeat this value; do not sum across records.
  process_cpu_percent : Double
  /// Full private memory footprint of the hosting process in bytes, or -1
  /// before measurement. Shared-process tasks repeat this value; do not sum.
  process_memory_bytes : Int64
  /// Platform task name, such as `Network Service`; empty when Chromium has
  /// none for the task.
  name : String
}

///|
pub extend AppTaskMetric with Eq::{not_equal, equal}

///|
pub extend AppTaskMetric with Debug::{to_repr}
