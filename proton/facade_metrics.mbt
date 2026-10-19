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
  @native.task_metrics() catch {
    error =>
      raise app_control_native_error("read the application task metrics", error)
  }
}
