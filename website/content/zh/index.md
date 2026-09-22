# Introduction

[English](../index.html)

Proton 是由原生 MoonBit 宿主和 Chromium 前端组成的桌面应用框架。前端可以使用 HTML/JavaScript，也可以使用编译到 JavaScript 的 MoonBit。公开应用入口为 `moonbit-community/proton`。

本文档对应已发布的 **Proton 0.3.3**。CLI 与 `proton_*` 模块使用同一发布版本。

## 章节

| 章节 | 内容 |
| --- | --- |
| Introduction | 架构、环境要求、项目结构及应用 API 概念 |
| [Tutorial](tutorial/index.md) | 从 minimal 开始，再构建完整的 isomorphic Todo 应用 |
| [Command Line Interface](cli.md) | 全部命令、选项、默认值与退出状态 |
| [Configuration](configuration.md) | `proton.project.json` 的全部字段及平台覆盖规则 |
| [Examples](examples/index.md) | 十个精选源码示例的行为、关键文件与限制 |
| [Release Notes](release-notes.md) | 已发布版本的变更 |

## 平台范围

支持的开发目标为 macOS Apple Silicon、Windows x64 和 Linux x64。原生能力的可用范围因平台而异。构建和打包在目标操作系统上执行。

分发产物携带 Chromium 和匹配的子进程 helper，因此会包含相应的运行时体积与子进程。Proton 不使用系统 WebView。

## API 参考

- [应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/)
- [扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.3/)
- [类型化契约](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.3/)
- [前端客户端](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.3/)
- [Rabbita 集成](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.3/)

生成的 API 文档提供完整签名；本站参考文档说明行为约定和 API 之间的关系。
