# Self-update scenario

This macOS scenario exercises `PendingUpdate.download()` and
`ApplicationContext.quit_and_install()` in a signed, headless application.
It uses the real application lifecycle, authenticated manifests and archives,
bundle replacement, and Launch Services relaunch.

```sh
e2e/self_update/run.sh
```

The runner requires MoonBit, Python 3, and Homebrew OpenSSL 3. It resolves the
installed CEF runtime and builds the helper unless `PROTON_RUNTIME_ROOT` and
`PROTON_HELPER_PATH` are already set. No application windows are opened.

The existing application and its replacement use different executable names.
Each case starts from a fresh copy of the old bundle and records lifecycle
events under `/tmp/proton-updater-e2e`:

- Installation happens after quit notifications and shutdown hooks, and the
  replacement acquires the single-instance lock and cleans the retained bundle.
- Rejecting either `before_quit` or `will_quit` retains the downloaded update,
  which can be installed by a later request.
- Forced exit discards the update and terminates without installing it.
- Ordinary quit discards the update and returns without installing it.
- A failing shutdown hook reports the cleanup error and prevents installation.

The runner also checks that downloading leaves the running application intact,
installation requires a prepared update, duplicate requests are harmless, and
no staging directories remain. Any failure makes the runner exit nonzero; each
process has a 120-second timeout, with its output retained in the work directory.

## Test environment

A loopback HTTPS server serves the release. Its temporary CA is trusted only
by the test process. Apple's LibreSSL ignores `SSL_CERT_FILE`, so the runner
uses `DYLD_LIBRARY_PATH` to select Homebrew OpenSSL for that process. It does
not change the system trust store or disable certificate verification. This
scenario does not validate the system TLS implementation.

Launch Services will not reliably launch bundles from the per-user temporary
directory (`$TMPDIR`, under `/var/folders`), so the default work directory is
under `/tmp`. `open` passes the test environment to the replacement. The
replacement reads its version from its own bundle and writes a completion event;
`open` returning success alone is not considered a successful restart.

Windows installer handoff and Linux AppImage relaunch are not covered by this
macOS scenario. Native transaction tests live in
`proton/internal/native/update_wbtest.mbt`. Deletion faults and restartable
cleanup have separate coverage in
`proton/internal/native/ffi/tests/update_cleanup.test.mjs`.
