# Browser decisions and observers

```sh
moon -C examples run 50_browser_control --target native
```

Run from a terminal to see decisions and browser events. The example first sets
three default decision handlers, then replaces each one. Only the final
`set_download_handler`, `set_certificate_error_handler`, and
`set_media_permission_handler` callbacks should run. An `ERROR: replaced ...`
line indicates that an old handler was incorrectly retained.

1. Select **Download file**. The final download handler prints the suggested
   filename and opens a save dialog. Cancel the dialog or select a destination;
   `on_download_event` reports progress and the terminal state.
2. Select **Request microphone**. The final media handler denies the request;
   the page displays the rejection. The callback requires a secure origin and
   a platform with an available media backend. A platform-level rejection can
   happen before Proton receives a request; check the terminal for the media
   decision rather than treating a JavaScript rejection alone as proof.
3. Select **Test certificate rejection**. With network access to
   `expired.badssl.com`, the final certificate handler reports and denies the
   invalid certificate. DNS, proxy, or network failures are not certificate
   decisions.
4. Select **Open popup in this window**. The main page's
   `WebContentsPolicy.new_window_handler` opens the URL in the current page.
5. Observe the browser event output: the first observer reports state and the
   second prints `second observer`. Both remain registered. Async observers
   may overlap; their completion order is not guaranteed.

Download, certificate, and media decisions apply to the application session,
including its child views. Popup policy belongs to this page. There is no
combined permission callback or implicit policy inheritance.

Navigation remains unrestricted in this example. Async navigation interception
has a [known replay limitation](https://github.com/moonbit-community/proton/issues/469)
for initial and cross-origin navigation. The `window-config` headless regression
in `e2e_fixtures/lifecycle_regressions.mbt` covers page-local navigation denial.
