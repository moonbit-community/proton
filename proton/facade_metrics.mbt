///|
fn AppProcessType::from_native(
  process_type : @native.AppProcessType,
) -> AppProcessType {
  match process_type {
    @native.AppProcessType::Unknown => Unknown
    @native.AppProcessType::Browser => Browser
    @native.AppProcessType::Gpu => Gpu
    @native.AppProcessType::Zygote => Zygote
    @native.AppProcessType::Utility => Utility
    @native.AppProcessType::Renderer => Renderer
    @native.AppProcessType::Extension => Extension
    @native.AppProcessType::Guest => Guest
    @native.AppProcessType::Plugin => Plugin
    @native.AppProcessType::SandboxHelper => SandboxHelper
    @native.AppProcessType::Worker => Worker
  }
}

///|
fn AppProcessMetric::from_native(
  metric : @native.AppProcessMetric,
) -> AppProcessMetric {
  AppProcessMetric::{
    task_id: metric.task_id,
    process_type: AppProcessType::from_native(metric.process_type),
    cpu_percent: metric.cpu_percent,
    memory_bytes: metric.memory_bytes,
    name: metric.name,
  }
}

///|
/// Returns the memory and CPU usage of every process the application owns,
/// corresponding to Electron's `app.getAppMetrics()`.
///
/// The list follows Chromium's task manager order: the browser process first,
/// then the GPU process when it runs separately, followed by the remaining
/// renderer, utility, and worker tasks.
///
/// Chromium measures processes only while something observes its task manager,
/// so the first call starts the sampling: it reports `-1` memory, and later
/// calls report the measured footprint and the CPU usage since the previous
/// sample. Electron's `pid`, idle wakeups, creation time, sandbox state, and
/// integrity level are not observable through CEF, so `task_id` identifies a
/// process instead.
pub fn ApplicationContext::app_metrics(
  self : ApplicationContext,
) -> Array[AppProcessMetric] raise AppControlError {
  ignore(self)
  let metrics = @native.process_metrics() catch {
    error =>
      raise app_control_native_error(
        "read the application process metrics", error,
      )
  }
  metrics.map(metric => AppProcessMetric::from_native(metric))
}
