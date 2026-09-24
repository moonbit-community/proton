///|
/// What kind of process one application task belongs to, using CEF's task
/// types.
pub(all) enum AppProcessType {
  Unknown
  Browser
  Gpu
  Zygote
  Utility
  Renderer
  Extension
  Guest
  Plugin
  SandboxHelper
  Worker
} derive(Debug, Eq)

///|
pub extend AppProcessType with Eq::{not_equal, equal}

///|
pub extend AppProcessType with Debug::{to_repr}

///|
/// Memory and CPU usage of one application process, corresponding to Electron's
/// `ProcessMetric`.
pub(all) struct AppProcessMetric {
  /// CEF's task identifier. Electron reports an operating-system pid instead.
  task_id : Int64
  process_type : AppProcessType
  /// CPU usage of the process since the previous sample, in the same scale as
  /// Electron's `percentCPUUsage`; 100% is one fully used core. Chromium
  /// reports zero until one sampling interval has passed.
  cpu_percent : Double
  /// Private memory footprint in bytes, or -1 while Chromium has not measured
  /// the process.
  memory_bytes : Int64
  /// Platform task name, such as "Network Service"; empty when Chromium has
  /// none for the task.
  name : String
} derive(Debug, Eq)

///|
pub extend AppProcessMetric with Eq::{not_equal, equal}

///|
pub extend AppProcessMetric with Debug::{to_repr}

///|
fn app_process_type_from_code(code : Int) -> AppProcessType {
  match code {
    1 => Browser
    2 => Gpu
    3 => Zygote
    4 => Utility
    5 => Renderer
    6 => Extension
    7 => Guest
    8 | 9 => Plugin
    10 => SandboxHelper
    11 | 12 | 13 => Worker
    _ => Unknown
  }
}

///|
/// Lists the processes the application currently owns, ordered like Chromium's
/// task manager: the browser process first, then the GPU process and the
/// remaining tasks.
pub fn process_metrics() -> Array[AppProcessMetric] raise NativeError {
  let count = Ref(0)
  check_status(@native_ffi.proton_app_metrics_count_ffi(count))
  let metrics : Array[AppProcessMetric] = []
  for index = 0; index < count.val; index = index + 1 {
    metrics.push(process_metric_at(index))
  }
  metrics
}

///|
fn process_metric_at(index : Int) -> AppProcessMetric raise NativeError {
  let task_id = Ref(0L)
  let process_type = Ref(0)
  let cpu_percent = Ref(0.0)
  let memory_bytes = Ref(0L)
  let name_required = Ref(0)
  let probe = @ffi.to_cstr("")
  check_status(
    @native_ffi.proton_app_metric_at_ffi(
      index, task_id, process_type, cpu_percent, memory_bytes, probe, 1, name_required,
    ),
  )
  let name = if name_required.val > 0 {
    let buffer = FixedArray::make(name_required.val + 1, b'\x00')
    check_status(
      @native_ffi.proton_app_metric_at_ffi(
        index,
        task_id,
        process_type,
        cpu_percent,
        memory_bytes,
        Bytes::from_array(buffer),
        buffer.length(),
        name_required,
      ),
    )
    @ffi.from_cstr(Bytes::from_array(buffer))
  } else {
    ""
  }
  AppProcessMetric::{
    task_id: task_id.val,
    process_type: app_process_type_from_code(process_type.val),
    cpu_percent: cpu_percent.val,
    memory_bytes: memory_bytes.val,
    name,
  }
}
