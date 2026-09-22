# HTML with sidecar assets

[中文](../zh/examples/46_asset_sidecar_resources.html)

An asset entry with separate JavaScript, CSS and worker files.

[46_asset_sidecar_resources](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/main.mbt), [app/app.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.html), [app/app.js](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.js), [app/app.css](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.css), [app/worker.js](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/worker.js)

## Behavior

asset() loads app.html with its sibling resources. The example also contains a second page for navigation.

```moonbit
///|
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

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 46_asset_sidecar_resources --target native
```

## Limits and interpretation

Run from the examples directory so the relative asset path resolves correctly. Deployments must package the complete resource tree, not only the HTML file.
