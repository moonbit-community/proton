# Window Aspect Ratio

This is a manual review example for Proton's Electron-style
`WindowHandle::set_aspect_ratio` API.

Run it with:

```sh
moon -C examples run 67_window_aspect_ratio --target native
```

Review the native window frame:

1. Choose **16:9**, then drag each native edge and corner. The live frame
   should preserve the ratio while the user resizes it.
2. Choose **1:1** and confirm the frame becomes square during interactive
   resizing.
3. Choose **Programmatic 900 x 500** while a ratio is active. The window
   should take the requested size even though it is not 16:9 or 1:1.
4. Choose **Clear ratio**, then confirm freeform interactive resizing works
   again without restarting the process.
5. Repeat the checks at a non-100% display scale where available.

Platform details:

- macOS uses the native content aspect-ratio constraint.
- Windows adjusts `WM_SIZING` rectangles for all eight resize directions.
- Linux updates GTK geometry aspect hints; the exact resize affordance depends
  on the desktop window manager.
- Headless runtimes report unsupported because they have no native frame.
- Passing `0.0` clears the ratio. Programmatic `set_size` is intentionally not
  constrained, matching Electron's `setAspectRatio` behavior.
