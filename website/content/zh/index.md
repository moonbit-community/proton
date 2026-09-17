# 用 MoonBit 构建桌面应用

[English](../index.html)

Proton 将原生 MoonBit 后端与 Chromium Web 前端组合成桌面应用。你可以从普通 HTML 开始，也可以使用 Rabbita，以 MoonBit 编写前后端。

[开始使用 →](installation.md) · [构建完整 Todo 示例](isomorphic.md)

```moonbit
async fn main {
  @proton.html("Hello Proton", "<h1>Hello from MoonBit</h1>")
  .load_config()
  .run_or_abort()
}
```

这段入口代码运行在生成的 minimal 项目中。[创建项目](first-app.md)一章会准备所需的包导入、依赖和应用标识。

## 为什么使用 Proton？

用 MoonBit 编写应用逻辑和原生集成，用 Web 技术呈现界面，通过命令和事件连接两端。使用 isomorphic 模板时，后端和 Rabbita 前端还可以共享 MoonBit 请求与响应类型。

Proton 会在分发产物中携带 Chromium 运行时，让前端在各支持平台上使用 Chromium 环境，同时也带来相应的运行时体积和子进程。它不使用操作系统自带的 WebView。

## 从哪里开始？

- **初次使用 Proton：** 准备环境，[创建最小应用](first-app.md)，然后了解[项目结构](project-structure.md)。
- **给应用增加功能：** 学习[调用后端](commands-events.md)、[发送事件](events.md)或[使用原生能力](capabilities.md)。
- **用 MoonBit 编写前后端：** 跟随 isomorphic 模板的[完整 Todo 示例](isomorphic.md)。
- **准备发布应用：** 阅读[构建与分发](packaging.md)。

[架构与进程模型](architecture.md)解释代码运行在哪里，以及两端各自适合管理哪些状态。

## 支持的平台

Proton 0.2.11 支持 macOS Apple Silicon、Windows x64 和 Linux x64。请在目标操作系统上构建和打包。某项原生能力支持的平台可能少于框架本身。

本指南假设你已掌握 MoonBit 基础，内容对应已发布的 **0.2.11**。跟随示例时，请让 CLI 与 Proton 各包保持在该版本。

## 参考资料

通过 [Proton API](https://mooncakes.io/docs/moonbit-community/proton@0.2.11/) 和[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.2.11/)查询签名与可选配置。[仓库示例目录](https://github.com/moonbit-community/proton/blob/main/examples/Readme.md)提供各项功能演示，但会跟随 main 更新，可能包含尚未发布的变化。
