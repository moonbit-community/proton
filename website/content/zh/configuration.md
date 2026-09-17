# 配置前端与资源

[English](../configuration.html)

Proton 可以加载内联 HTML、URL、本地文件或打包资源，不强制使用独立前端工具。本章解释 isomorphic 模板的可用配置，以及开发入口如何对应打包后的入口。

## 项目配置

isomorphic 模板使用以下 **`proton.project.json`** 配置。运行前端命令前，先安装一次 Warren：

```sh
moon install moonbit-community/warren@0.3.2
```

已发布的 CLI 0.3.0 生成的是 `moonx --target native` 命令。请只将 `frontend.before_dev` 和 `frontend.before_build` 替换成下方的值，保留其他项目配置。仓库 main 已包含此修正，但已发布的 CLI 0.3.0 尚未包含。Warren 0.3.2 没有已发布的 Wasm 可执行文件，因此不能只删除 `--target native`。

配置直接调用已安装的 `warren` 命令：

```json
{
  "identifier": "com.example.todo-app",
  "backend": {
    "path": ".",
    "package": "backend/app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "warren dev --browser-entry main --direct --port 4300",
    "before_build": "warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Todo App",
    "version": "0.1.0",
    "output": "dist"
  }
}
```

请保留你为应用选择的 identifier。这份配置适用于 isomorphic 工作区；minimal 项目构建的是 `app` 包，没有 `frontend` 部分。

## 开发流程如何运行

在项目根目录执行 `proton_cli dev` 后，CLI 会：

1. 在 `frontend.path` 中运行 `frontend.before_dev`。
2. 等待 `frontend.dev_url` 可访问。
3. 在 `backend.path` 中构建 `backend.package`，并让原生应用使用开发 URL 启动。

配置中的 URL 和服务器端口必须一致。当 CLI 负责启动服务器时，会拒绝已被占用的端点。如果你自行管理前端服务器，使用：

```sh
proton_cli dev --no-frontend
```

此时前端必须已经能通过配置的 URL 访问。普通浏览器中的预览不包含原生 bridge。

## 生产资源如何加载

后端入口仍然保留为：

```moonbit
@proton.asset("Todo App", "frontend/dist/index.html")
```

这是模板已有构建器链中的入口表达式，不是完整的 `main`。

`proton_cli build` 执行 `frontend.before_build`、检查 `frontend.dist`，再构建原生后端。前端命令在 `frontend.path` 中运行，所以其中的 `dist` 对应项目里的 `frontend/dist`。

不要将生产 asset 入口替换为硬编码的开发 URL。打包应用必须能在没有开发服务器时加载自己的构建文件。

## 使用其他前端

任何能生成 HTML、CSS 和 JavaScript 的前端都可以提供界面。将前端命令、URL 和输出目录替换为所选工具的配置，并相应修改后端 asset 路径。

Proton CLI 不会替你配置前端框架。需要确保生产输出能从打包后的资源位置工作，包括样式、脚本、图片及前端路由 URL。请测试实际打包应用，开发服务器运行成功并不能验证这些路径。

## 携带附加文件

后端需要读取的文件，可以在已有的 `package` 对象中添加资源路径：

```json
{
  "resources": ["assets"]
}
```

这是需要合并的片段，不是完整项目文件。在项目根目录创建 `assets/` 并放入文件，打包时会复制声明的资源。后端以 `@proton.resource_dir()` 为基准定位 `assets/...`，开发和打包运行均采用这一方式。

持久化、可写的用户数据应放在安装资源目录之外。修改元数据后执行 `proton_cli package --dry-run`，分发前再验证实际打包结果。

## 标识与运行时配置

`identifier` 是稳定标识，`product_name` 是显示文字，`package.version` 是你自己的应用版本，三者都不同于 Proton 的依赖版本。

使用 `.load_config()` 加载受管理的元数据；不使用受管理配置的应用可以改用 `.identifier(...)`。窗口选项、命令绑定和 capability 仍放在 MoonBit 构建器中，不放在这份 JSON 中。
