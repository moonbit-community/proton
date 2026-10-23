# Environment requirements

The installation commands below target Proton 0.6.0 (not yet published); they become available after publication. See [Release Notes](../release-notes/releases.md) for API migration details.

Proton 0.6.0 supports the following host build environments. Native builds and packages target the host operating system; cross-compilation is not provided by the Proton CLI.

| Platform | Architecture | Build requirements |
| --- | --- | --- |
| macOS | Apple Silicon | Xcode Command Line Tools, `clang` |
| Windows | x64 | Visual Studio C++ Build Tools, MSVC and Windows SDK; developer terminal |
| Linux | x64 | C/C++ build tools, pkg-config, X11/RandR and GTK development libraries; graphical environment for execution |

On Ubuntu 24.04, the dependency set includes `build-essential`, `pkg-config`, `libglib2.0-dev`, `libx11-dev`, `libxrandr-dev`, `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `libnotify-dev`, `libnss3`, `libgbm1` and `libasound2t64`. Package names and runtime compatibility vary by distribution.

Linux shell operations also require desktop services: `open` and `trash_item` use the `gio` executable; `reveal_item` uses `dbus-send` and a file manager implementing `org.freedesktop.FileManager1` on the session bus. Power-event watching uses GIO and the system bus. GIO remains optional at runtime for applications that do not watch power events; see [monitor availability](application-api.md#extensions-and-capabilities).

NSIS is required only for NSIS output. Signing identities and notarization credentials are distribution requirements, not prerequisites for local development.

## Tool commands

| Tool | Role | Installation or inspection |
| --- | --- | --- |
| MoonBit | Compiler, package manager and runtime tools | [Official installation](https://www.moonbitlang.com/download/); `moon version` |
| Proton CLI | Project development and packaging | `moon install moonbit-community/proton_cli@0.6.0`; `proton_cli --version` |
| Warren | Isomorphic frontend dev server and build | `moon install moonbit-community/warren@0.4.5`; `warren --help` |
| Node.js / npm | Warren's JavaScript build tooling | [Node.js installation](https://nodejs.org/en/download); `node --version`, `npm --version` |

Use the MoonBit `latest` toolchain channel for Proton 0.6.0. The sources require explicit `Int32` / `UInt32` types, the updated labeled-parameter syntax, and JSON parsing with `preserve_number_repr`. The older 2026-10-12 stable toolchain is insufficient. Select `latest` when installing MoonBit and check the installed version with `moon version`.

MoonBit's binary directory must be on PATH. Minimal applications with inline HTML do not require Warren or Node.js. `moonx`'s deprecated native mode is not required by the documented frontend commands.

## Runtime installation

`proton_cli cef setup` resolves the release's Chromium runtime and matching source-built helper. Its initial run needs network access and may take several minutes. Arbitrary CEF downloads do not satisfy the release contract.

| Location | Content |
| --- | --- |
| `~/.proton/store/` | Immutable shared CEF SDK/runtime installations |
| `~/.proton/helpers/` | Helpers selected by platform and Proton version |
| `PROTON_RUNTIME_STORE` | Optional absolute override for runtime storage |

Runtime/helper files are not copied into project source. They are assembled into distributable applications during packaging. CLI and Proton module versions must agree. `proton_cli doctor` checks project configuration, tools, runtime and helper without changing them.

To create an application with these tools, follow the [minimal application tutorial](../tutorial/first-app.md). The repository checkout below is needed only to run the examples in this book.

## Source checkout and runtime

Examples use the repository workspace. Clone the release commit, install the [required tools](installation.md), and set up its runtime once:

```sh
git clone https://github.com/moonbit-community/proton.git
cd proton
git checkout 91ffc6210878af84a639d773efdc71669dc47430
moon update
proton_cli cef setup
```

After setup, run the command listed on the chosen [example page](../examples/01_run.md) from this repository root. These commands use the repository workspace, not a scaffolded application.
