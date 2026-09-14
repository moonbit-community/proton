# Taskbar Status

This is a manual review example for Proton's Electron-style taskbar status
APIs: `WindowHandle::set_progress_bar` with explicit modes,
`WindowHandle::set_overlay_icon`, and `WindowHandle::set_thumbnail_tooltip`.

Run it with:

```sh
moon -C examples run 78_taskbar_status --target native
```

Review the application and the Windows taskbar button:

1. Choose **25%** and **75%**. The taskbar button should show a determinate
   progress bar filled to that fraction.
2. Choose **Indeterminate**. The progress bar should animate.
3. Choose **Error**. The progress bar should turn red and keep the value.
4. Choose **Paused**. The progress bar should turn yellow and keep the value.
5. Choose **Clear**. The progress bar should disappear.
6. Choose **Show badge**. A red badge should appear in the bottom right corner
   of the taskbar icon. Choose **Clear badge** to remove it.
7. Rest the pointer over the taskbar button. The thumbnail tooltip should read
   what the input holds; type a new value, choose **Apply tooltip**, and check
   it again.

Every step reports the applied call in the status line, and each accepted call
is appended to the log, so a rejected call is visible without guessing.

Electron parity notes: the progress value semantics are Electron's — a negative
value clears the indicator, `0.0` through `1.0` is determinate, and a value
above `1.0` is indeterminate — and the explicit modes mirror Electron's `mode`
option. The overlay image follows Electron's Windows rendering rule: it is
scaled to the 16x16 overlay area, centered, and clipped to a circle. The mode
option, the overlay icon, and the thumbnail tooltip are Windows-only in
Electron; macOS and Linux accept the calls and do nothing, which is what this
example shows there.
