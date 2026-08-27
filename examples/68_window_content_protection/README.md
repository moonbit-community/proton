# Window Content Protection

This manual example exercises Electron's `WindowHandle::set_content_protection`.

Run:

```sh
moon -C examples run 68_window_content_protection --target native
```

Enable protection, then use a screen recording or capture tool to verify the
window is excluded or blacked out. Disable it and confirm normal capture works.
On macOS, newer ScreenCaptureKit clients may still capture protected windows;
this follows Electron's documented platform limitation. Linux treats the API
as a successful no-op. Headless runtimes report unsupported.
