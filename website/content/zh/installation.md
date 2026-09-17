# 环境准备

[English](../installation.html)

创建应用前，先安装 MoonBit 和当前操作系统的原生构建工具。minimal 模板不需要前端构建工具，isomorphic 模板则会使用 Warren。

## macOS

Proton 0.3.0 支持 Apple Silicon。在终端中安装 Xcode Command Line Tools：

```sh
xcode-select --install
```

完成弹出的安装流程，再确认编译器可用：

```sh
clang --version
```

本地开发不需要签名身份。签名与公证属于[分发](packaging.md)阶段。

## Windows

使用 64 位 Windows 开发环境。安装 [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)，选择 **使用 C++ 的桌面开发**、MSVC x64/x86 构建工具和 Windows SDK。

打开 **Developer PowerShell for Visual Studio** 或 **x64 Native Tools Command Prompt**，执行：

```text
cl
```

命令应输出 Microsoft C/C++ 编译器信息。如果找不到命令，请确认使用的是开发者终端，而不是普通终端。SDK 还提供了生成可执行文件图标所需的资源编译器。只有生成 NSIS 安装器时才需要安装 NSIS。

## Linux

使用 x64 图形桌面环境。以 Ubuntu 24.04 为例，安装构建工具与桌面依赖：

```sh
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libx11-dev libxrandr-dev \
  libgtk-3-dev libwebkit2gtk-4.1-dev libnotify-dev \
  libnss3 libgbm1 libasound2t64
```

其他发行版的包名不同。以上命令用于准备开发环境，并不意味着构建产物可以在所有 Linux 发行版运行；请在准备支持的发行版上实际测试应用。

## MoonBit 和 Proton CLI

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，并将其二进制目录加入 PATH。安装完成后重新打开终端，检查工具，然后安装本指南使用的 CLI 版本：

```sh
moon version
moon install moonbit-community/proton_cli@0.3.0
proton_cli --version
```

最后一个命令应输出 `0.3.0`。如果找不到 `proton_cli`，检查 MoonBit 的二进制目录是否已加入 PATH；如果运行了其他版本，检查 PATH 中是否存在优先级更高的旧程序。

跟随 isomorphic 教程时，还需要安装 [Node.js](https://nodejs.org/en/download)。Warren 构建会调用 npm 工具压缩 JavaScript：

```sh
node --version
npm --version
```

安装一次前端工具，并确认 PATH 中可以找到它：

```sh
moon install moonbit-community/warren@0.3.2
warren --help
```

已发布的 Proton CLI 0.3.0 仍生成已弃用的 `moonx --target native` 前端命令。创建 isomorphic 项目后，请按[前端配置](configuration.md)替换这两条命令。minimal 模板不需要 Warren。

## 创建项目后安装运行时

先[创建项目](first-app.md)，再在该项目目录中执行：

```sh
moon update
proton_cli cef setup
proton_cli doctor
```

setup 下载匹配的 Chromium 运行时与子进程 helper，需要网络连接，首次安装可能耗时数分钟。各项目共享 `~/.proton/store` 和 `~/.proton/helpers` 中的不可变安装。

doctor 检查项目、工具链、运行时和 helper，不会修改它们。先处理检查报告中的问题，再启动开发。让 `proton_cli`、`proton` 和所有 `proton_*` 包保持同一版本；自行下载任意 CEF 版本不能替代 setup。
