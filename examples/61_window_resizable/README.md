# Window Resizable

This is a manual review example for Proton's Electron-style
`WindowHandle::set_resizable` API.

Run it with:

```sh
moon -C examples run 61_window_resizable --target native
```

Review the native window frame:

1. Drag the lower-right edge and confirm the window resizes.
2. Choose **Disable resizing**, then try the same edge gesture. The frame
   should stay fixed.
3. Choose **Enable resizing** and resize again without restarting the app.
4. Repeat the checks at a narrow and a wide window size.
5. On Windows with display scaling above 100%, confirm the frame and renderer
   remain aligned.

Platform details:

- macOS adds or removes `NSWindowStyleMaskResizable` on the live `NSWindow`.
- Windows toggles the native thick-frame/maximize styles and refreshes the
  non-client frame; existing size hints remain in effect.
- Linux delegates to GTK's `gtk_window_set_resizable`; the exact resize affordance
  depends on the desktop window manager.
- Headless runtimes report unsupported because there is no native window frame.
