# Process control and metrics

## Single-instance ownership

`App.single_instance()` uses the application identity to select one owning process. Later instances forward URL, document or reopen activation and return after the primary loop accepts it. Acceptance does not wait for asynchronous launch handlers to complete. Forwarding has a five-second deadline; failure does not kill the primary or start another owner.

`ApplicationContext.has_single_instance_lock()` queries ownership and `release_single_instance_lock()` releases it during the run. Releasing does not terminate the process. Choose deliberately whether another process may now become the owner. Register launch-input handling for both initial and forwarded activations.

## App state versus window state

Application focus, hide/show, active/hidden queries and readiness describe the application. A window handle controls one window. A hidden window remains alive, and an application with KeepRunning can remain alive with no windows. Always provide an explicit exit path for background applications.

## Task metrics

`ApplicationContext.task_metrics()` returns `AppTaskMetric` rows for Chromium tasks. A renderer and multiple workers can share a process. Task ids identify tasks; the hosting process usage in multiple rows may be identical because it belongs to the shared process. Do not sum rows into a process or application total.

CPU is zero until a sampling interval has passed; 100% represents one fully used core. Memory is -1 before measurement, not zero bytes. The fields are `process_cpu_percent` and `process_memory_bytes`. These observations do not confer ownership of a process and should not be used to kill helpers independently of Proton's lifecycle.
