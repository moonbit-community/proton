# Window Size Limits

This is a manual review example for Proton's Electron-style
`WindowHandle::set_minimum_size` and `WindowHandle::set_maximum_size` APIs.

Run it with:

```sh
moon -C examples run 62_window_size_limits --target native
```

Review the native window frame:

1. Set the minimum to `480 x 360`, then drag a corner smaller.
2. Set the maximum to `1100 x 760`, then drag a corner larger.
3. Clear each constraint independently and confirm the other remains active.
4. On Windows with display scaling above 100%, confirm the native frame obeys
   the same limits.

Platform details:

- macOS updates the window content minimum and maximum sizes.
- Windows applies the limits through `WM_GETMINMAXINFO` and preserves the
  independent `set_resizable` state.
- Linux updates GTK geometry hints; the exact resize affordance depends on
  the desktop window manager.
- Headless runtimes report unsupported because they have no native frame.

Passing `(0, 0)` clears a constraint. Both dimensions must be positive when a
constraint is set, and minimum/maximum pairs may not conflict.
