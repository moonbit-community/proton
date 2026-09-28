///|
fn AppTaskType::from_native(task_type : @native.AppTaskType) -> AppTaskType {
  match task_type {
    @native.AppTaskType::Unknown => Unknown
    @native.AppTaskType::Browser => Browser
    @native.AppTaskType::Gpu => Gpu
    @native.AppTaskType::Zygote => Zygote
    @native.AppTaskType::Utility => Utility
    @native.AppTaskType::Renderer => Renderer
    @native.AppTaskType::Extension => Extension
    @native.AppTaskType::Guest => Guest
    @native.AppTaskType::Plugin => Plugin
    @native.AppTaskType::SandboxHelper => SandboxHelper
    @native.AppTaskType::Worker => Worker
  }
}

///|
fn AppTaskMetric::from_native(metric : @native.AppTaskMetric) -> AppTaskMetric {
  AppTaskMetric::{
    task_id: metric.task_id,
    task_type: AppTaskType::from_native(metric.task_type),
    process_cpu_percent: metric.process_cpu_percent,
    process_memory_bytes: metric.process_memory_bytes,
    name: metric.name,
  }
}

///|
/// Returns browser tasks with the CPU and memory usage of their hosting processes.
///
/// Each record describes a task, not a unique process. Tasks sharing a process
/// repeat its full resource usage; do not sum the values across records.
/// `task_id` identifies a task, not a PID, and no process grouping key is exposed.
///
/// The list follows Chromium's task manager order: browser first, then GPU
/// when separate, followed by the remaining tasks. The first call starts
/// sampling; memory is -1 before measurement and CPU is zero until a sampling
/// interval has passed. Observation continues until the runtime shuts down.
pub fn ApplicationContext::task_metrics(
  self : ApplicationContext,
) -> Array[AppTaskMetric] raise AppControlError {
  ignore(self)
  let metrics = @native.task_metrics() catch {
    error =>
      raise app_control_native_error("read the application task metrics", error)
  }
  metrics.map(metric => AppTaskMetric::from_native(metric))
}
