# Taskbar Status

This is a manual review example for Proton's Electron-style taskbar status
APIs: `WindowHandle::set_progress_bar` with explicit modes,
`WindowHandle::set_overlay_icon`, `WindowHandle::set_thumbnail_tooltip`, and
`WindowHandle::set_thumbar_buttons` together with
`App::on_thumbar_button_click`.

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
8. Choose **Show buttons**. The thumbnail should show three buttons — previous,
   play, and next. The play button uses the `nobackground` flag, so it has no
   button border while the other two do.
9. Click each toolbar button. The page log should report
   `taskbar button clicked: previous`, `play`, or `next`, which is the
   application handler receiving the button id.
10. Choose **Clear buttons** and click where a button used to be. The toolbar
    should be empty and no further click should reach the application.

Every step reports the applied call in the status line, and each accepted call
is appended to the log, so a rejected call is visible without guessing.

Electron parity notes: the progress value semantics are Electron's — a negative
value clears the indicator, `0.0` through `1.0` is determinate, and a value
above `1.0` is indeterminate — and the explicit modes mirror Electron's `mode`
option. The overlay image follows Electron's Windows rendering rule: it is
scaled to the 16x16 overlay area, centered, and clipped to a circle. The mode
option, the overlay icon, and the thumbnail tooltip are Windows-only in
Electron; macOS and Linux accept the calls and do nothing, which is what this
example shows there. `set_thumbar_buttons` mirrors Electron's
`setThumbarButtons`, including the seven-button limit, the button flags, and the
Windows limitation that the button slots are claimed by the first call. Electron
attaches one callback per button; Proton reports the button `id` through
`App::on_thumbar_button_click` instead, so rebuilding the toolbar cannot
silently retarget a click. That call reports `false` on macOS and Linux, the
same result Electron returns there.
