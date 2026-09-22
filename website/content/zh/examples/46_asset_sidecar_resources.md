# HTML 与静态资源

[English](../../examples/46_asset_sidecar_resources.html)

资源入口配合独立 JavaScript、CSS 和 worker 文件。

[46_asset_sidecar_resources](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/main.mbt), [app/app.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.html), [app/app.js](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.js), [app/app.css](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/app.css), [app/worker.js](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/46_asset_sidecar_resources/app/worker.js)

## 行为

asset() 加载 app.html 及其相邻资源。示例还提供第二个页面以观察导航。

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

## 运行

需满足[运行环境要求](../installation.md)。在仓库根目录执行：

```sh
moon -C examples run 46_asset_sidecar_resources --target native
```

## 限制与使用边界

从 examples 目录运行，使相对资源路径正确解析。分发时必须包含完整资源树，不能只带 HTML。
