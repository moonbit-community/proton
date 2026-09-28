///|
/// The kind of browser task represented by a metric.
pub(all) enum AppTaskType {
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
pub extend AppTaskType with Eq::{not_equal, equal}

///|
pub extend AppTaskType with Debug::{to_repr}

///|
/// A browser task and the resource usage of its hosting process.
///
/// Multiple tasks can share a process and repeat its full CPU and memory
/// usage. These values are not per-task usage and must not be summed across
/// records. The task ID is not a PID; no process grouping key is available.
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
  /// Platform task name, such as "Network Service"; empty when Chromium has
  /// none for the task.
  name : String
} derive(Debug, Eq)

///|
pub extend AppTaskMetric with Eq::{not_equal, equal}

///|
pub extend AppTaskMetric with Debug::{to_repr}

///|
/// Decodes Proton-owned task type codes from proton_native.h.
fn app_task_type_from_code(code : Int) -> AppTaskType {
  match code {
    1 => Browser
    2 => Gpu
    3 => Zygote
    4 => Utility
    5 => Renderer
    6 => Extension
    7 => Guest
    8 => Plugin
    9 => SandboxHelper
    10 => Worker
    _ => Unknown
  }
}

///|
/// Lists browser tasks with hosting-process usage, ordered like Chromium's
/// task manager: the browser process first, then the GPU process and the
/// remaining tasks.
pub fn task_metrics() -> Array[AppTaskMetric] raise NativeError {
  let count = Ref(0)
  check_status(@native_ffi.proton_task_metrics_count_ffi(count))
  let metrics : Array[AppTaskMetric] = []
  for index = 0; index < count.val; index = index + 1 {
    metrics.push(task_metric_at(index))
  }
  metrics
}

///|
fn task_metric_at(index : Int) -> AppTaskMetric raise NativeError {
  let task_id = Ref(0L)
  let task_type = Ref(0)
  let process_cpu_percent = Ref(0.0)
  let process_memory_bytes = Ref(0L)
  let name_required = Ref(0)
  let probe = @ffi.to_cstr("")
  check_status(
    @native_ffi.proton_task_metric_at_ffi(
      index, task_id, task_type, process_cpu_percent, process_memory_bytes, probe,
      1, name_required,
    ),
  )
  let name = if name_required.val > 0 {
    let buffer = FixedArray::make(name_required.val + 1, b'\x00')
    check_status(
      @native_ffi.proton_task_metric_at_ffi(
        index,
        task_id,
        task_type,
        process_cpu_percent,
        process_memory_bytes,
        Bytes::from_array(buffer),
        buffer.length(),
        name_required,
      ),
    )
    @ffi.from_cstr(Bytes::from_array(buffer))
  } else {
    ""
  }
  AppTaskMetric::{
    task_id: task_id.val,
    task_type: app_task_type_from_code(task_type.val),
    process_cpu_percent: process_cpu_percent.val,
    process_memory_bytes: process_memory_bytes.val,
    name,
  }
}
