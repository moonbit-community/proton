# Window Controls

Manual review for Electron-style `WindowHandle::set_minimizable`,
`WindowHandle::set_maximizable`, `WindowHandle::set_closable`, and
`WindowHandle::set_focusable`.
`WindowHandle::set_fullscreenable`.
`WindowHandle::set_has_shadow`, `set_ignore_mouse_events`,
`set_background_color`, `set_kiosk`, `set_visible_on_all_workspaces`, and
`set_enabled`.
Also covers `set_content_size`, `content_size`, `set_menu`, `set_icon`,
`set_parent`, and `set_window_button_visibility`.

```sh
moon -C examples run 69_window_controls --target native
```

1. Toggle each capability and inspect the native title bar.
2. Disable close and confirm the native close button and user close shortcut do
   not close the window.
3. Confirm disabling minimize, maximize, or close affects only that capability,
   while ordinary edge resizing remains available.
4. With close still disabled, use **Programmatic close** as the final check and
   confirm the application can still close its own window.
5. Disable focus and click the window; on macOS and Windows it should not
   become the active window. Re-enable focus before the final close check.
6. Disable fullscreenable and confirm entering fullscreen is blocked; exiting
   an already-fullscreen window remains possible.
7. On macOS, disable shadow and inspect the window edge against the desktop,
   then re-enable it. Windows and Linux currently accept this as a no-op.

macOS and Windows update native controls. Linux follows Electron and treats
these capability setters as successful no-ops. Headless runtimes report
unsupported.

8. Use **Interaction test** to disable input, change the background, enable
all-workspace visibility, and disable the window. Re-enable with **Enable all**.
9. Enter kiosk and confirm it exits automatically after five seconds; use
**Exit kiosk** as the immediate programmatic exit check.
10. Review content-size changes, runtime menu replacement/clearing, native icon
    loading from a local path, parent/modal relationship, and macOS traffic-light
    visibility. Parent and modal controls include explicit clear/reset actions.
