# Application Control

Manual review for Proton's Electron-style application-level control:
`ApplicationContext::focus`, `hide`, `show`, `is_active`, `is_hidden`, and the
`is_ready()` query.

Run it from a terminal so every action and the reported state stay visible:

```sh
moon -C examples run 82_app_control --target native
```

Nothing in this example changes system settings or writes files. The only
cleanup is closing the window.

## Review steps

1. Before pressing anything, read the terminal. The first three lines must be
   `is_ready before App::run = false`, `is_ready in app_lifecycle.on_start =
   false`, and `is_ready after startup = true`: readiness becomes true only
   after startup hooks completed and the initial window is ready. The page's
   **isReady** row must read `true` after any action, because the renderer can
   load before startup finished.
2. Press **Focus**. macOS must bring the application to the front. On Windows
   and Linux the application's first visible window must be focused instead.
   The terminal prints `focus requested`.
3. Minimize the window or switch to another application, then press
   **Focus with steal**. macOS must activate this application even though
   another application was frontmost. The option is ignored outside macOS.
4. macOS only: press **Hide app**. The window must disappear without being
   minimized, the terminal must print `hide requested`, and the **isHidden**
   row must read `true`. Press **Show app** and confirm the window reappears
   without becoming the active application, with **isHidden** back to `false`.
5. macOS only: compare **isActive** with reality. Activate this application
   from the Dock or by clicking its window, run any action, and confirm the row
   is `true`; switch to another application and confirm it becomes `false`.
6. Windows and Linux: the **isActive** and **isHidden** rows must read
   `unsupported`, and **Hide app**/**Show app** must report
   `hiding the application is not available on this platform` instead of
   silently doing nothing.

## Platform matrix

- macOS (`darwin-arm64`): readiness, `focus`, and the AppKit group are
  exercised locally by the headless `app-control` lifecycle regression; the
  visible activation, hide, and show behavior still needs this manual review.
- Windows and Linux: runtime behavior is not verified locally. Both must report
  the AppKit group as unsupported and focus the first visible window. Copyable
  prompt:
  ```text
  Build examples on <platform> and run `moon -C examples run 82_app_control
  --target native`. Follow README review steps 1, 2, 6 (and 4-5 on macOS).
  Report the terminal `[app-control]` lines, the isReady/isActive/isHidden
  rows, and whether focus reached the application's first visible window.
  ```
