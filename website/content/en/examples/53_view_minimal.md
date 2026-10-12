# Embedded browser view

This example places a child browser beside a sidebar in the main window. It demonstrates the distinction between the main page and a separately navigable browser view, including explicit bounds for the child.

[53_view_minimal](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/53_view_minimal) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/53_view_minimal/main.mbt)

## Behavior

`WindowConfig.views` adds a browser at x=288 with an 832 × 720 viewport. It loads example.com separately from the host HTML.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn main {
  @proton.App(
    @proton.WindowConfig(
      "Minimal View",
      @proton.AppEntry::Html(sidebar),
      width=1120,
      height=720,
      views=[
        (
          "browser",
          @proton.view("https://example.com/", width=832, height=720, x=288),
        ),
      ],
    ),
  )
  .debug(enabled=true)
  .identifier("dev.proton.53-view-minimal")
  .run_or_abort()
}
```

The main browser renders the sidebar; `WindowConfig.views` creates a second browser inside the same native window. x=288 reserves the sidebar width, and the child loads example.com independently. This is useful for a host shell with an embedded page, rather than a separate top-level window.

The example intentionally has fixed geometry. A production layout must recompute child bounds after resizing and decide how remote navigation is handled. Granting commands to the local host page does not mean remote child content should receive the same capabilities.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 53_view_minimal --target native
```

## Limits and interpretation

The remote page requires network access. Bounds are fixed in this minimal example; responsive view layout belongs to the application. Parent shutdown ends the child lifetime.
