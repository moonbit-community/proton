# Browser Task Metrics

Run `moon -C examples run 85_task_metrics --target native`.

The example displays `ApplicationContext::task_metrics()` and logs each sample.
Use **Sample now** or **sample every second** to refresh it. The first query
starts sampling; subsequent queries show measured CPU and memory values.

Each row is a browser task. `task id` is not a PID. CPU and memory are the
**full usage of the hosting process**, not the task's individual usage.
Multiple tasks can share a process and repeat its usage: **do not sum rows**.
The API provides no process grouping key and is not equivalent to Electron's
`app.getAppMetrics()`.

Check that browser and GPU tasks lead the table, unmeasured memory displays
`not measured`, and closing the window shuts down the application normally.
The headless `task-metrics` E2E case also creates two dedicated workers and
checks that both retain distinct task identities and the `Worker` type.
