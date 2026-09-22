# 架构与进程模型

[English](../../introduction/architecture.html)

Proton 应用包含原生宿主和 Web 前端。即使两端都用 MoonBit 编写，它们也运行在不同环境中，通过消息通信。

## 原生宿主

后端是一个 MoonBit 可执行文件，负责启动 Proton、管理原生窗口、注册命令处理器和访问操作系统功能。

需要跨窗口共享或独立于界面校验的应用状态，适合保存在后端。Todo 模板中，后端管理待办列表与修订号，前端管理当前输入文字、加载状态和错误展示。

后端使用 `moonbitlang/async`。Proton 在初始化阶段将原生事件循环接入调度器。应用调用 `.run()` 或 `.run_or_abort()` 即可，不需要再创建一套 UI 轮询循环。

## Web 前端

Chromium 渲染 HTML、CSS 和 JavaScript。Rabbita 将 MoonBit 界面代码编译为在此环境中运行的 JavaScript。即使类型来自同一个共享模块，前端变量也不是后端值的引用。

CEF 通过与版本匹配的 helper 管理渲染器等子进程。应用运行时看到多个进程是正常现象。让 Proton 管理生命周期，才能完成正常的退出流程。

## 命令与事件

**命令**将请求发送给已注册的后端处理器，返回结果或失败。当调用方需要答案时使用命令，例如加载文档、创建 Todo、查询快照。

**事件**向正在监听的前端发送通知，适合报告变化或进度。它不是持久队列，不会补发订阅之前错过的通知。

```text
Frontend                 Native backend
   | -- command(request) --> |
   | <-- response/failure -- |
   |                         |
   | <-- event(payload) ---- |
```

`proton_contract` 描述路由与载荷类型，`proton_client` 供 MoonBit 前端调用，`proton_rabbita` 将请求和订阅接入 Rabbita 组件。普通 JavaScript 则可以使用注入的 bridge，见[从前端调用后端](commands-events.md)。

共享类型不等于共享内存。值通过序列化数据跨越 bridge，载荷应只包含接收方需要的信息。

## 原生能力授权

应用命令暴露业务操作，扩展则暴露文件访问等可复用的宿主能力。添加 capability 会同时安装扩展后端，并向指定渲染器目标授权。

默认目标是主入口。第二个窗口不一定需要同样的权限，应根据功能选择操作、目录和目标。具体见[原生能力](capabilities.md)。

## 开发与分发

使用内联 HTML 时，后端直接携带页面字符串。使用前端工具时，`proton_cli dev` 启动开发服务器并使用其开发 URL。普通浏览器能预览这个 URL，但没有 Proton 的原生 bridge。

生产构建生成静态前端资源，打包再将资源、后端可执行文件、Chromium 和对应 helper 组合起来。因此，前端预览成功不等于完整应用已测试通过，分发时也不能只复制后端可执行文件。
