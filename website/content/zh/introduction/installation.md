# 运行环境要求

[English](../../introduction/installation.html)

Proton 0.3.3 支持以下宿主构建环境。原生构建与打包面向当前操作系统，Proton CLI 不提供跨操作系统交叉编译流程。

| 平台 | 架构 | 构建要求 |
| --- | --- | --- |
| macOS | Apple Silicon | Xcode Command Line Tools、`clang` |
| Windows | x64 | Visual Studio C++ Build Tools、MSVC、Windows SDK；开发者终端 |
| Linux | x64 | C/C++ 构建工具、pkg-config、X11/RandR 和 GTK 开发库；执行时需要图形环境 |

Ubuntu 24.04 的依赖包括 `build-essential`、`pkg-config`、`libx11-dev`、`libxrandr-dev`、`libgtk-3-dev`、`libwebkit2gtk-4.1-dev`、`libnotify-dev`、`libnss3`、`libgbm1` 和 `libasound2t64`。不同发行版的包名及运行兼容性可能不同。

NSIS 仅用于 NSIS 格式产物。签名身份和公证凭据属于分发要求，不是本地开发的前置条件。

## 工具命令

| 工具 | 职责 | 安装或检查 |
| --- | --- | --- |
| MoonBit | 编译器、包管理器和运行工具 | [官方安装](https://www.moonbitlang.com/download/)；`moon version` |
| Proton CLI | 项目开发与打包 | `moon install moonbit-community/proton_cli@0.3.3`；`proton_cli --version` |
| Warren | isomorphic 前端开发服务器与构建 | `moon install moonbit-community/warren@0.3.3`；`warren --help` |
| Node.js / npm | Warren 的 JavaScript 构建工具 | [Node.js 安装](https://nodejs.org/en/download)；`node --version`、`npm --version` |

MoonBit 二进制目录必须在 PATH 中。使用内联 HTML 的 minimal 应用不需要 Warren 或 Node.js。本文档的前端命令不依赖已弃用的 native `moonx` 模式。

## 运行时安装

`proton_cli cef setup` 解析该版本的 Chromium 运行时及从源码构建的匹配 helper。首次执行需要网络，可能耗时数分钟。任意下载的 CEF 不能替代版本匹配的安装。

| 位置 | 内容 |
| --- | --- |
| `~/.proton/store/` | 不可变、共享的 CEF SDK／运行时安装 |
| `~/.proton/helpers/` | 按平台和 Proton 版本选择的 helper |
| `PROTON_RUNTIME_STORE` | 可选的运行时存储绝对路径覆盖 |

运行时和 helper 不写入项目源码，而是在打包时组装到应用产物中。CLI 和 Proton 模块版本应保持一致。`proton_cli doctor` 检查项目配置、工具、运行时和 helper，不修改它们。

创建项目和首次运行的逐步操作仅放在[最小应用教程](../tutorial/first-app.md)中。
