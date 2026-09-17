# Prerequisites

[中文](zh/installation.html)

Before creating an application, install MoonBit and the native build tools for your operating system. The minimal template needs no frontend build tool; the isomorphic template adds Warren.

## macOS

Proton 0.3.0 supports Apple Silicon. Install Xcode Command Line Tools from Terminal:

```sh
xcode-select --install
```

Complete the installer, then confirm that the compiler is available:

```sh
clang --version
```

You do not need a signing identity to develop locally. Signing and notarization belong to [distribution](packaging.md).

## Windows

Use a 64-bit Windows development environment. Install [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022), selecting **Desktop development with C++**, MSVC x64/x86 build tools, and a Windows SDK.

Open **Developer PowerShell for Visual Studio** or **x64 Native Tools Command Prompt**, then check:

```text
cl
```

The command should print the Microsoft C/C++ compiler banner. If it is not found, use the developer terminal rather than an ordinary terminal. The SDK also provides the resource compiler used for executable icons. NSIS is only needed when producing an NSIS installer.

## Linux

Use an x64 graphical desktop. For an Ubuntu 24.04 development environment, install the build and desktop libraries:

```sh
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libx11-dev libxrandr-dev \
  libgtk-3-dev libwebkit2gtk-4.1-dev libnotify-dev \
  libnss3 libgbm1 libasound2t64
```

Other distributions use different package names. These packages provide a development environment; they are not a promise that every Linux distribution can run the resulting package. Test your application on the distributions you intend to support.

## MoonBit and the Proton CLI

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and add its binary directory to PATH. Open a new terminal after installation. Confirm the tools work, then install the CLI version used by this guide:

```sh
moon version
moon install moonbit-community/proton_cli@0.3.0
proton_cli --version
```

The last command should report `0.3.0`. If `proton_cli` cannot be found, check that MoonBit's binary directory is on PATH. If another version runs, check for an older executable earlier on PATH.

For the isomorphic tutorial, also install [Node.js](https://nodejs.org/en/download). Its Warren build invokes npm tooling to minimize JavaScript:

```sh
node --version
npm --version
```

Install the frontend tool once, then verify that it is on PATH:

```sh
moon install moonbit-community/warren@0.3.2
warren --help
```

The published Proton CLI 0.3.0 still generates deprecated `moonx --target native` frontend commands. After creating an isomorphic project, replace those two commands as shown in [frontend configuration](configuration.md). The minimal template does not need Warren.

## Install the runtime after creating a project

[Create a project](first-app.md) first, then run from that project directory:

```sh
moon update
proton_cli cef setup
proton_cli doctor
```

Setup downloads the matching Chromium runtime and subprocess helper. It requires network access and can take several minutes the first time. Projects share immutable installations in `~/.proton/store` and `~/.proton/helpers`.

Doctor checks the project, toolchain, runtime, and helper without modifying them. Resolve its findings before starting development. Keep `proton_cli`, `proton`, and `proton_*` packages on the same release; an arbitrary CEF download is not a substitute for setup.
