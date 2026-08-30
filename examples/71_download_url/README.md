# Programmatic Download

Manual review for Electron-style `BrowserHandle::download_url`, using Proton's
existing download approval, progress, and cancellation handlers.

```sh
moon -C examples run 71_download_url --target native
```

1. Keep **Temporary review file** selected, start the inline `data:` URL, and
   confirm the page reports approval, progress, and `complete` without
   navigating away.
2. Open the reported temporary path and confirm it contains
   `Hello from Proton downloadUrl`.
3. Select **Save dialog**, start the inline URL again, choose a destination,
   and confirm the saved content and terminal event.
4. Select **Use 250 MB test URL**, start the download, then press
   **Cancel active** while progress is visible and confirm a `cancelled` event.

Repeat the same checks on macOS, Windows, and Linux. The 250 MB cancellation
check requires network access. Electron's optional custom `downloadURL`
request headers are intentionally absent because CEF does not expose them.
