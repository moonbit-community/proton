# Proton 技术文档

[English](../index.html)

Proton 是由原生 MoonBit 宿主和 Chromium 前端组成的桌面应用框架。前端可以使用 HTML/JavaScript，也可以使用编译到 JavaScript 的 MoonBit。公开应用入口为 `moonbit-community/proton`。

本文档对应已发布的 **0.3.0**。CLI 与 `proton_*` 依赖使用同一发布版本。文档包含 CLI 0.3.0 所需的 Warren 手动配置；修正后的生成器已进入 main，尚未发布。

## 文档索引

| 领域 | 内容 |
| --- | --- |
| [架构](architecture.md) | 进程、执行环境、所有权和通信 |
| [项目结构](project-structure.md) | 模块、包导入、配置与生成产物 |
| [运行环境](installation.md) | 支持平台、必需工具和运行时安装 |
| [应用生命周期](lifecycle.md) | 入口来源、应用身份、启动与退出 |
| [项目配置](configuration.md) | 字段、默认值和路径解析 |
| [CLI](cli.md) | 命令、执行行为和失败条件 |
| [命令](commands-events.md)与[事件](events.md) | 类型、注册、传递、取消与错误 |
| [窗口](windows.md) | 声明、句柄、子视图与关闭行为 |
| [能力与权限](capabilities.md) | 扩展安装、渲染器目标与权限范围 |
| [打包](packaging.md) | 产物、平台覆盖、签名与资源 |
| [诊断](debugging.md) | 日志、DevTools 与错误分类 |

[Tutorial](tutorial/index.md) 单独收录逐步练习：最小应用、命令、事件、多窗口、文件访问和完整 Todo 应用。参考文档可以独立查阅，不要求读者先创建教程项目。

## 平台范围

支持的开发目标为 macOS Apple Silicon、Windows x64 和 Linux x64。原生能力的可用范围因平台而异。构建和打包在目标操作系统上执行。

分发产物携带 Chromium 和匹配的子进程 helper，因此会包含相应的运行时体积与子进程。Proton 不使用系统 WebView。

## API 参考

- [应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.0/)
- [扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.0/)
- [类型化契约](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.0/)
- [前端客户端](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.0/)
- [Rabbita 集成](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.0/)

生成的 API 文档提供完整签名；本站参考文档说明行为约定和 API 之间的关系。
