# Proton

Proton is a MoonBit framework for building native desktop applications with a
web frontend. It embeds Chromium through CEF and bundles the browser engine
with the application on each supported platform.

- Native windows, embedded browser views, menus and application lifecycle.
- Typed commands and events between the frontend and native MoonBit code.
- Operating-system capabilities through extensions, with explicit permissions.
- Development tooling and packaging for macOS Apple Silicon, Windows x64 and
  Linux x64.

[English documentation](https://moonbit-community.github.io/proton/) ·
[中文文档](https://moonbit-community.github.io/proton/zh/)

## Quick start

Install [MoonBit and the native build prerequisites](website/content/en/introduction/installation.md)
for your platform. The default template uses Rabbita for its MoonBit frontend
and Warren to serve and build it; install Node.js/npm as described in the
prerequisites. Run these commands outside another MoonBit workspace:

```sh
moon install moonbit-community/proton_cli@0.4.0
moon install moonbit-community/warren@0.4.5
proton_cli new my-app --yes
cd my-app
moon update
proton_cli cef setup
proton_cli dev
```

The default `isomorphic` template creates a working Todo application with three
modules: a shared command contract, a Rabbita frontend and a native backend.
`dev` starts the configured frontend server and opens the desktop application.
The list is held in memory and resets when the application restarts.

`cef setup` downloads the release-matched Chromium runtime and subprocess
helper into a shared user-level store. Its first run requires network access
and can take several minutes. Keep the CLI and application dependencies on the
same Proton release.

Follow the [Todo tutorial](website/content/en/tutorial/isomorphic.md) to extend
the generated application. For a smaller app with inline HTML and no frontend
tooling, use `--template minimal` and follow the
[minimal application tutorial](website/content/en/tutorial/first-app.md).

## Application API

An application's native entry point configures an `App` and runs it. For
example, an inline-HTML app inside a generated 0.4.0 minimal project can use:

```moonbit
async fn main {
  @proton.html("Hello Proton", "<h1>Hello from MoonBit</h1>")
  .config(@proton.load_config())
  .run_or_abort()
}
```

`config` applies the project's configuration before `run_or_abort()`.
Entries can also load URLs, files or bundled assets. Applications register
commands explicitly; shared contracts describe their payloads and results.
See the [application API reference](website/content/en/introduction/application-api.md)
for lifecycle, windows, browser contents, commands, events and capabilities.

## Build and package

From the generated project directory, stop the development app, then build:

```sh
proton_cli build -- --release
```

Packaging assembles the executable, frontend assets, browser runtime and helper
into a distribution for the current host platform. Review the
[packaging prerequisites](website/content/en/command-line-interface/packaging.md#icon-and-tool-prerequisites)
before running:

```sh
proton_cli package --dry-run
proton_cli package --release
```

The default scaffold has no icons. Linux AppImage packaging requires a PNG
icon and `appimagetool`; NSIS output on Windows requires NSIS. The
[packaging reference](website/content/en/command-line-interface/packaging.md)
explains formats, installation scope, resources, signing and notarization.
`--release` does not enable signing, and a dry run does not create an artifact.

For configuration or startup problems, run `proton_cli doctor` and consult the
[diagnostics reference](website/content/en/command-line-interface/debugging.md).

## Documentation

| Topic | Reference |
| --- | --- |
| Architecture and processes | [How Proton runs an application](website/content/en/introduction/architecture.md) |
| Tutorials | [Minimal app](website/content/en/tutorial/first-app.md), [complete Todo app](website/content/en/tutorial/isomorphic.md) |
| Command Line Interface | [All commands and options](website/content/en/command-line-interface/commands.md) |
| Configuration | [All `proton.project.json` fields](website/content/en/configuration/project.md) |
| Application API | [Types, lifecycle and platform behavior](website/content/en/introduction/application-api.md) |
| Examples | [Runnable examples](examples/Readme.md) |
| Release notes | [Changes and migration guidance](website/content/en/release-notes/releases.md) |
| Extensions | [Available capability modules](extensions/README.md) |
| Standalone packaging | [Package prebuilt executables](package/README.md) |
| CDP automation | [Connect external automation clients](cdp/README.mbt.md) |

## Contributing

See the [maintainer guide](AGENTS.md) for repository structure, build and test
commands, native ownership rules and contribution requirements.

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
