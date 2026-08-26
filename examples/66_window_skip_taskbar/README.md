# Window Skip Taskbar

This is a manual review example for Proton's Electron-style
`WindowHandle::set_skip_taskbar` API.

Run it with:

```sh
moon -C examples run 66_window_skip_taskbar --target native
```

Review the operating-system window shell:

1. On Windows, confirm the application starts with a normal taskbar tab.
2. Enable **Skip taskbar** and confirm the taskbar tab disappears while the
   native window remains open and usable.
3. Disable **Skip taskbar** and confirm the taskbar tab returns without
   restarting the process.
4. Repeat the toggle several times and confirm focus, movement, resizing, and
   close behavior remain normal.
5. On macOS and Linux, confirm both calls succeed and the window remains usable;
   Electron intentionally treats this API as a no-op on those platforms.

Platform details:

- Windows uses `ITaskbarList::DeleteTab` and `ITaskbarList::AddTab`.
- macOS and Linux follow Electron's successful no-op behavior.
- Headless runtimes report unsupported because there is no native window shell.
