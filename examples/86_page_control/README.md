# Page History and Inserted CSS

Manual review for Proton's page-control surface:
`BrowserHandle::navigation_history()` and
`BrowserHandle::insert_css()` / `BrowserHandle::remove_inserted_css()`,
matching Electron's `webContents.navigationHistory`,
`webContents.insertCSS`, and `webContents.removeInsertedCSS`. `ViewHandle`
exposes the same three operations for web contents views.

Run the example from a terminal:

```sh
moon -C examples run 86_page_control --target native
```

Every action prints one `[page-control]` line, and the table shows the entries
of the current browser together with the active index and the Chromium page
transition of each entry.

## Review steps

1. The terminal must print `application started`, then
   `startup entries=1 active_index=0`, and the table must show the single
   `https://proton.localhost/` entry marked as active.
2. Press **Insert CSS**. The marker `inserted stylesheet` appears in the bottom
   left corner of the page, the header reports `key <n>`, and the terminal
   prints `insert_css key=<n>`. This is `webContents.insertCSS`.
3. Press **Load second page**. The window shows the second document and the
   table lists two entries with the second one active. The inserted stylesheet
   belonged to the first document, so the marker is gone.
4. Press **Back** and confirm the table reports the first entry as active
   again. Pressing **Remove inserted CSS** now removes the stylesheet that the
   first document still owns; because the document reloaded, the key no longer
   matches and the call stays a successful no-op.
5. Insert CSS again on the restored page, then load the second page and confirm
   the marker disappears with the navigation while the terminal keeps printing
   the keys it used.
6. Close the window. The application exits normally and nothing outside its
   session data directory changes.

## Reading the values

- `active` is the zero-based index Chromium reports for the current entry; the
  header shows it one-based together with the entry count, matching Electron's
  `navigationHistory.getActiveIndex()` plus `length()`.
- `transition` is Chromium's page-transition type: `link`, `typed`,
  `auto-bookmark`, `auto-subframe`, `manual-subframe`, `generated`,
  `auto-toplevel`, `form-submit`, `reload`, `keyword`, or `keyword-generated`.
  Entries that carry redirect or back/forward qualifiers also report them.
- Inserted stylesheets are served as a `<style data-proton-css-key="...">`
  element, so page scripts can see them. Chromium applies them to the document
  that inserted them; navigation drops them, like Electron's `insertCSS`.
- Electron's `navigationHistory.goToIndex`, `clear`, and `restore` have no CEF
  counterpart. Use **Back**, `BrowserHandle::back()`, and
  `BrowserHandle::forward()` to move through the history.

## Platform matrix

- macOS (`darwin-arm64`): the headless e2e `page-control` lifecycle case runs
  locally and covers the entry list, the active index, the inserted stylesheet,
  the removal, and the entry added by a later navigation. The visible desktop
  review above still needs a human.
- Windows and Linux: the same case runs in CI on both platforms. Repeat the
  steps above and report the `[page-control]` lines together with the table.
