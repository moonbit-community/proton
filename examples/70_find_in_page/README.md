# Find In Page

Manual review for Electron-style `BrowserHandle::find_in_page`,
`ViewHandle::find_in_page`, their result events, and stop behavior.

```sh
moon -C examples run 70_find_in_page --target native
```

1. Search the host page for `Proton` and confirm multiple matches are
   highlighted in the left pane.
2. Confirm the first search selects an active match, then use **Next** and
   **Previous** and confirm the active match and request id change for each call.
3. Search the web contents view and confirm only the right pane is highlighted.
4. Enable case matching and compare `Proton` with `proton`.
5. Use **Stop and keep selection**, then **Stop and clear selection**, and
   confirm the current highlight is respectively preserved and removed.

Repeat the same checks on macOS, Windows, and Linux. The status line reports
selection rectangles in the target web contents coordinate space.
