# Windows titlebar prototype preview

The Windows geometry test has an opt-in interactive preview of the private
host-drawn titlebar. It uses the real Proton window procedure and an HWND that
stands in for a browser child. Normal tests do not show the window. The
prototype does not change the default DWM overlay or expose an application API.

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
