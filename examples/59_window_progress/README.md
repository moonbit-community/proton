# Window Progress

This is a manual review example for Proton's Electron-style
`WindowHandle::set_progress_bar` API on macOS.

Run it with:

```sh
moon -C examples run 59_window_progress --target native
```

Review the application and its Dock icon:

1. Move the slider to 25%, 50%, and 75%. The Dock indicator should remain
   determinate and track each value.
2. Choose **Indeterminate**. The Dock indicator should animate continuously.
3. Choose **Clear**. The custom Dock indicator should disappear and the normal
   application icon should return.
4. Choose **Run cycle**. The indicator should advance smoothly from 0% to 100%
   and clear when the cycle completes.
5. Set a visible progress value and close the window. The Dock indicator should
   be removed during window teardown.

Electron value semantics are preserved: negative values clear the indicator,
values from `0.0` through `1.0` are determinate, and values above `1.0` are
indeterminate. macOS exposes one Dock indicator for the application, so the
most recent window call wins and any negative value clears it.
