# Multi-window commands

This example exposes command operations to two windows in one application. It shows how window declarations, renderer grants and caller identity work together without giving every page implicit access.

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/45_bridge_multi_window) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/45_bridge_multi_window/main.mbt)

## Behavior

The identify command returns both the supplied label and CommandContext.window_id(). Calls from different windows retain their originating window identity.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn main {
  @proton.html(
    "Bridge Multi A",
    page_html("A"),
    width=520,
    height=420,
    debug=true,
  )
  .add_window(
    "secondary",
    "Bridge Multi B",
    @proton.AppEntry::Html(page_html("B")),
    width=520,
    height=420,
    open_on_start=false,
  )
  .capability(@proton_extension.capability(multi_window_extension()), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
  ])
  .app_lifecycle(
    on_start=async fn(context) { ignore(context.windows().open("secondary")) },
    on_shutdown=fn(_state) {  },
  )
  .identifier("dev.proton.45-bridge-multi-window")
  .run_or_abort()
}
```

One extension implementation serves two independently authorized renderer targets. The secondary declaration has open_on_start=false and is opened explicitly in the application start hook. The handler returns context.window_id(), proving that caller identity comes from the host context rather than the page's label.

Reuse shared business handlers, but list each intended target explicitly. Keep per-window UI state on the frontend and shared state in the host. Delayed calls can overlap; do not infer response ownership from whichever window currently has focus.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## Limits and interpretation

The optional delay_ms makes overlapping requests visible. A logical window name identifies an application window, not a globally reusable native handle.
