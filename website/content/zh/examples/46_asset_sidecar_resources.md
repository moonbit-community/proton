# HTML 与静态资源

本例加载 HTML 入口及独立的 JavaScript、CSS 和 worker 文件，展示页面从应用资源加载时如何组织文件和相对路径。

[46_asset_sidecar_resources](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources/main.mbt), [app/app.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources/app/app.html), [app/app.js](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources/app/app.js), [app/app.css](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources/app/app.css), [app/worker.js](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/46_asset_sidecar_resources/app/worker.js)

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

## 实现说明

asset 入口指定资源树中的 HTML 文档。相邻脚本、样式和 worker 源码仍是独立文件，因此打包后必须保持相对 URL 有效。扩展注册与资源入口选择是两件独立的事。

迁移时保留资源目录布局，并配置打包包含它。关闭开发服务器后验证产物；开发 URL 正常不证明附属资源已经打包。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 46_asset_sidecar_resources --target native
```

## 限制与使用边界

从 examples 目录运行，使相对资源路径正确解析。分发时必须包含完整资源树，不能只带 HTML。
