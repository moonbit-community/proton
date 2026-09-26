# Application Metrics

Manual review for Proton's application process metrics:
`ApplicationContext::app_metrics()`, matching Electron's
`app.getAppMetrics()`.

Run the example from a terminal:

```sh
moon -C examples run 85_app_metrics --target native
```

The example samples every process the application owns, prints one
`[app-metrics]` line per sample, and renders the same table in the window. The
page samples once on load, and **Sample now** or **sample every second** keeps
the table live.

## Review steps

1. The first terminal line must report the process list without a memory
   footprint, for example
   `sample: 6 processes, measured=false browser#0 cpu=0 mem_mb=-1 ...`. This is
   the snapshot before Chromium's task manager has measured anything.
2. Wait for the next samples. Memory appears for the browser process first and
   for the remaining processes within the following sampling interval (about
   one second, two on macOS); CPU stays `0` until one interval has passed and
   then reports the usage since the previous sample.
3. Confirm the process list leads with `browser`, followed by `gpu` when it
   runs separately, the `utility` processes, and the `renderer` processes for
   the window and its page.
4. Press **Sample now** a few times and confirm the memory values move and the
   CPU values reflect what the application is doing. Press **sample every
   second** and interact with the window to see the renderer and browser values
   change.
5. Close the window. The application exits normally and nothing outside its
   session data directory changes.

## Reading the values

- `cpu` is the CPU usage since the previous sample; `100%` is one fully used
  core, matching Electron's `percentCPUUsage`.
- `mem_mb` is the private memory footprint, or `-1` while Chromium has not
  measured the process. The table shows `not measured` for those rows.
- `task id` is CEF's task identifier. Electron reports an operating-system
  `pid` instead, and the idle wakeups, creation time, sandbox state, and
  integrity level of Electron's `ProcessMetric` have no CEF counterpart.
- Electron names renderer tasks `Tab`; Proton reports the process type `renderer`
  and keeps Chromium's task `name`, which is empty when Chromium reports none.

## Platform matrix

- macOS (`darwin-arm64`): the headless e2e `app-metrics` lifecycle case is
  verified locally and covers the sampling wait, the task types, and the
  browser-first order. The visible desktop review above still needs a human.
- Windows and Linux: the same case runs in CI on both platforms. Repeat the
  steps above and report the terminal lines with the per-process values.
