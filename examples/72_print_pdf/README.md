# Print And PDF

Manual review for Electron-style `BrowserHandle::print` and
`BrowserHandle::print_to_pdf`, including PDF options and completion events.

```sh
moon -C examples run 72_print_pdf --target native
```

1. Use **System print** and confirm the platform print flow opens with two
   printable pages and no dark control bar. Cancel the dialog after review.
2. Create the standard PDF and confirm the status reports `complete`, the
   request id matches, backgrounds render, and header/footer page numbers are
   present.
3. Create the landscape PDF and confirm wide paper, compact margins, and the
   four-color calibration strip.
4. Create the CSS A4 PDF and confirm the `@page` size is preferred and content
   remains unclipped across both pages.

Repeat on macOS, Windows, and Linux. PDF output is cross-platform. Linux uses
CEF's required PDF paper-size handler; interactive system printing still
depends on the desktop print stack available in the session.
