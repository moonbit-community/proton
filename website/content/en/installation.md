# Environment requirements

[中文](zh/installation.html)

Proton 0.3.0 supports the following host build environments. Native builds and packages target the host operating system; cross-compilation is not provided by the Proton CLI.

| Platform | Architecture | Build requirements |
| --- | --- | --- |
| macOS | Apple Silicon | Xcode Command Line Tools, `clang` |
| Windows | x64 | Visual Studio C++ Build Tools, MSVC and Windows SDK; developer terminal |
| Linux | x64 | C/C++ build tools, pkg-config, X11/RandR and GTK development libraries; graphical environment for execution |

On Ubuntu 24.04, the dependency set includes `build-essential`, `pkg-config`, `libx11-dev`, `libxrandr-dev`, `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `libnotify-dev`, `libnss3`, `libgbm1` and `libasound2t64`. Package names and runtime compatibility vary by distribution.

NSIS is required only for NSIS output. Signing identities and notarization credentials are distribution requirements, not prerequisites for local development.

## Tool commands

| Tool | Role | Installation or inspection |
| --- | --- | --- |
| MoonBit | Compiler, package manager and runtime tools | [Official installation](https://www.moonbitlang.com/download/); `moon version` |
| Proton CLI | Project development and packaging | `moon install moonbit-community/proton_cli@0.3.0`; `proton_cli --version` |
| Warren | Isomorphic frontend dev server and build | `moon install moonbit-community/warren@0.3.2`; `warren --help` |
| Node.js / npm | Warren's JavaScript build tooling | [Node.js installation](https://nodejs.org/en/download); `node --version`, `npm --version` |

MoonBit's binary directory must be on PATH. Minimal applications with inline HTML do not require Warren or Node.js. `moonx`'s deprecated native mode is not required by the documented frontend commands; published CLI 0.3.0 needs the [configuration adjustment](configuration.md#warren-commands-in-030).

## Runtime installation

`proton_cli cef setup` resolves the release's Chromium runtime and matching source-built helper. Its initial run needs network access and may take several minutes. Arbitrary CEF downloads do not satisfy the release contract.

| Location | Content |
| --- | --- |
| `~/.proton/store/` | Immutable shared CEF SDK/runtime installations |
| `~/.proton/helpers/` | Helpers selected by platform and Proton version |
| `PROTON_RUNTIME_STORE` | Optional absolute override for runtime storage |

Runtime/helper files are not copied into project source. They are assembled into distributable applications during packaging. CLI and Proton module versions must agree. `proton_cli doctor` checks project configuration, tools, runtime and helper without changing them.

Project creation and first execution are covered only in the [minimal tutorial](tutorial/first-app.md).
