# Window Opacity

This is a manual review example for Proton's Electron-style
`WindowHandle::set_opacity` API.

Run it with:

```sh
moon -C examples run 65_window_opacity --target native
```

Review the complete native window:

1. Place the window above another application or a high-contrast desktop area.
2. Choose **85% opacity**, **60% opacity**, and **35% opacity**. Confirm the
   desktop behind the native frame becomes progressively more visible.
3. Move the slider through intermediate values and confirm the opacity changes
   when the slider is released.
4. Choose **100% opaque** and confirm the window returns to its original
   appearance without restarting.
5. Confirm the title bar, native frame, and renderer change together rather
   than only changing the web page contents.

Platform details:

- macOS updates `NSWindow.alphaValue`.
- Windows enables `WS_EX_LAYERED` and updates the frame alpha with
  `SetLayeredWindowAttributes`.
- Linux updates the top-level GTK widget opacity; the compositor and desktop
  session determine the exact visual result.
- Values are clamped to `0.0..1.0`. Headless runtimes report unsupported.
