# Multi-window commands

This example creates windows on demand within one application and grants command access to an explicit family of window IDs. It uses the unreleased runtime creation API.

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/main/examples/45_bridge_multi_window) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/main/examples/45_bridge_multi_window/main.mbt)

## Behavior

The identify command returns both the supplied label and CommandContext.window_id(). Calls from different windows retain their originating window identity.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn main {
  let config = @proton.WindowConfig(
    "Bridge Multi B",
    @proton.AppEntry::Html(page_html("B")),
    width=520,
    height=420,
  )
  let windows : Ref[@proton.WindowManager?] = Ref(None)
  let next_id = Ref(0)
  let extension = multi_window_extension(() => {
    next_id.val += 1
    let id = "chat-" + next_id.val.to_string()
    ignore(windows.val.unwrap().create(id, config))
    id
  })
  @proton.html(
    "Bridge Multi A",
    page_html("A"),
    width=520,
    height=420,
    debug=true,
  )
  ..identifier("dev.proton.45-bridge-multi-window")
  ..single_instance()
  ..capability(@proton_extension.capability(extension), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
    @proton.RendererTarget::entry_prefix("chat-"),
  ])
  ..setup(context => {
    windows.val = Some(context.windows())
    ignore(context.windows().create("secondary", config))
  })
  .run_or_abort()
}
```

The application creates `secondary` during setup using `WindowManager.create`, then creates another `chat-N` window whenever the user clicks **New window**. All secondary instances reuse `config`, with independent browser state and command identity. No window pool or predeclared IDs are needed.

The extension is registered once. Exact grants authorize `main` and `secondary`; `entry_prefix("chat-")` authorizes the entry pages of new chat windows. The handler returns `context.window_id()`, so routing uses the caller's host identity rather than a label supplied by JavaScript. `single_instance()` keeps one application process while allowing multiple windows.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## Limits and interpretation

The optional delay_ms makes overlapping requests visible. A logical window name identifies an application window, not a globally reusable native handle.
