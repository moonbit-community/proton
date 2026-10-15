# Independent page policies

```sh
moon -C examples run 52_web_contents_view --target native
```

The host page is loaded from assets. Its sidebar controls a child browser added
through `WindowHandle.add_view` after the window becomes ready.

- Select **Open host popup (denied)** in the sidebar. The host's
  `WindowConfig.web_contents_policy` prints `host popup denied`; no page opens.
- Select **Open view popup** in the initial child page. Its independent
  `ViewConfig.web_contents_policy` prints `view popup opened in current view`;
  the child displays **Opened in the child view**, and the host sidebar remains
  present. The child does not inherit the host's denial policy.
- Enter a URL or use the site buttons to navigate the child. Navigation is
  allowed by default because neither page installs a navigation handler.
- Start the host and view tones before navigating away from the initial child
  page, then mute each independently. Zoom and navigation controls continue to
  apply only to the child.

These popup actions use real button clicks so Chromium supplies a user gesture.
Calling `window.open` from a host `eval` without a gesture can be suppressed by
Chromium before Proton receives the request.
