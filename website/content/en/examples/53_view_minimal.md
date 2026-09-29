# Embedded browser view

A declarative child browser alongside a host sidebar.

[53_view_minimal](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/53_view_minimal) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/53_view_minimal/main.mbt)

## Behavior

with_view() adds a browser at x=288 with an 832 × 720 viewport. It loads example.com separately from the host HTML.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 53_view_minimal --target native
```

## Limits and interpretation

The remote page requires network access. Bounds are fixed in this minimal example; responsive view layout belongs to the application. Parent shutdown ends the child lifetime.

## Key code and design

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
  .with_view(
    "browser",
    @proton.view("https://example.com/", width=832, height=720, x=288),
  )
  .identifier("dev.proton.53-view-minimal")
  .run_or_abort()
}
```

The main browser renders the sidebar; with_view creates a second browser inside the same native window. x=288 reserves the sidebar width, and the child loads example.com independently. This is useful for a host shell with an embedded page, rather than a separate top-level window.

The example intentionally has fixed geometry. A production layout must recompute child bounds after resizing and decide how remote navigation is handled. Granting commands to the local host page does not mean remote child content should receive the same capabilities.
