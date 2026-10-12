# HTML with sidecar assets

This example loads an HTML entry together with separate JavaScript, CSS and worker files. It demonstrates the resource layout needed when a page is served from application assets rather than a development server.

[46_asset_sidecar_resources](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources/main.mbt), [app/app.html](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources/app/app.html), [app/app.js](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources/app/app.js), [app/app.css](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources/app/app.css), [app/worker.js](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/46_asset_sidecar_resources/app/worker.js)

## Behavior

asset() loads app.html with its sibling resources. The example also contains a second page for navigation.

```moonbit
async fn main {
  let app = @proton.asset(
    "Asset Sidecar Resources",
    "46_asset_sidecar_resources/app/app.html",
    width=760,
    height=500,
    debug=true,
  ).capability(@proton_extension.capability(extension()))
  app.identifier("dev.proton.46-asset-sidecar-resources").run_or_abort()
}
```

## Implementation

The asset entry names an HTML document within the resource tree. Its neighboring scripts, styles and worker source remain separate files, so their relative URLs must remain valid after packaging. The extension registration is independent of asset selection.

When adapting this example, keep the resource tree layout and configure packaging to include it. Verify a packaged application with the development server stopped. A working development URL does not demonstrate that sidecar files were packaged.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 46_asset_sidecar_resources --target native
```

## Limits and interpretation

Run from the examples directory so the relative asset path resolves correctly. Deployments must package the complete resource tree, not only the HTML file.
