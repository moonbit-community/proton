# Windows titlebar overlay checks

The Windows geometry test has an opt-in interactive preview of the host-drawn
buttons. It uses the real Proton window procedure and an HWND that stands in
for a browser child. Normal tests do not show the window.

From the repository root in PowerShell, with the installed CEF runtime's `bin`
directory on `PATH`:

```powershell
$env:PROTON_TEST_TITLEBAR_PREVIEW = '1'
moon test proton/internal/native/ffi/tests/window_geometry --target native `
  --filter 'custom titlebar height drives hit testing and child clipping'
Remove-Item Env:PROTON_TEST_TITLEBAR_PREVIEW
```

- Press **F6** to switch between the 32-DIP light and 64-DIP dark rows. The text
  and three glyphs should stay vertically centered, with one continuous row
  background and no second set of caption buttons.
- On Windows 11 with Snap Layouts enabled, hover the maximize button and check
  that the Windows flyout appears. Move the pointer away before testing clicks.
- Click maximize, restore and minimize; then restore from the taskbar and close
  via the rightmost button. Closing the window ends the test.

To exercise the public API with a real browser child, run
`moon run examples/48_titlebar_overlay --target native` with the local CEF runtime
and subprocess configured as in the [examples guide](../../../../../../examples/Readme.md).
Switch between 32 DIP, 64 DIP and System buttons. In fullscreen, the buttons
and geometry should disappear and then return on exit. Use a Windows UI
Automation inspector to find three native buttons in custom mode and check that
invoking Maximize resizes the window and changes the action to Restore. On a
multi-monitor setup, repeat after dragging the window between displays with
different scaling.
