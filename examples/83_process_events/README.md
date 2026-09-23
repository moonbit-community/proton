# Process-Level Events

Manual review for Proton's process-level application events:
`.on_session_created(...)`, `.on_window_created(...)`,
`.on_web_contents_created(...)`, and `.on_render_process_gone(...)`, matching
Electron's `session-created`, `browser-window-created`,
`web-contents-created`, and `render-process-gone`.

Run it from a terminal so every event stays visible:

```sh
moon -C examples run 83_process_events --target native
```

The example uses `.single_instance()` with `.session_partition("process-events")`,
so the session review also shows a persistent profile instead of a temporary
one. Nothing else in this example changes system state; the only cleanup is
closing the window.

## Review steps

1. Before the window appears, the terminal must print
   `session-created partition=process-events data=<user data>/sessionData/process-events`.
   That line comes from the session Proton created for this run.
2. `browser-window-created main` must print once, followed by
   `web-contents-created browser:main` for the window's main page.
3. Press **Add probe view**. The terminal must print
   `web-contents-created view:main/probe`, and **web contents created** must
   count 2. Press **Close probe view** and confirm the count stays at 2: the
   creation event describes the object, not the current layout.
4. Kill the renderer to review `render-process-gone`. Find the `cef_process`
   helper that carries `--type=renderer` (Activity Monitor on macOS, Task
   Manager on Windows, or `pgrep -fl 'type=renderer'` on Linux/macOS) and kill
   it. The terminal must print
   `render-process-gone browser:main reason=killed exit_code=<code>` (a crash
   reports `reason=crashed`), **renderers gone** must count 1, and the
   application must keep running: this is an event, not a fatal error.
5. After the renderer died, press **Add probe view** or **Refresh counts** to
   confirm the application still answers. Reload the page from the DevTools
   console or restart the example to recover the page.
6. Close the window. `lifecycle shutdown` prints last and the process exits
   with status 0.

## Platform matrix

- macOS (`darwin-arm64`, headless regression): session, window, and web
  contents creation plus a killed renderer are covered locally by the
  `process-events` lifecycle regression; the visible review above still needs a
  desktop session.
- Windows and Linux: runtime behavior is not verified locally. The same
  lifecycle regression runs in CI on both, and the manual steps above apply
  unchanged except for the way a helper process is located and killed.

## Known difference

Electron also emits `child-process-gone` for GPU, utility, and plugin
processes. CEF's public API reports renderer termination per browser but never
signals other child process exits, so Proton has no equivalent event and does
not expose one that could never fire.
