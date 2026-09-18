# Proton documentation

[中文](zh/index.html)

Proton is a desktop application framework with a native MoonBit host and a Chromium frontend. Applications can use HTML/JavaScript or a MoonBit frontend compiled to JavaScript. The public application API is `moonbit-community/proton`.

This documentation describes published **0.3.0**. CLI and `proton_*` dependencies share that release version. The current documentation includes the manual Warren configuration required by CLI 0.3.0; the corrected generator is in main but has not been released.

## Documentation map

| Area | Contents |
| --- | --- |
| [Architecture](architecture.md) | Processes, execution environments, ownership and transport |
| [Project layout](project-structure.md) | Modules, package imports, configuration and generated output |
| [Environment](installation.md) | Supported platforms, required tools and runtime installations |
| [Application lifecycle](lifecycle.md) | Entry sources, identity, startup and shutdown |
| [Project configuration](configuration.md) | Configuration fields, defaults and path resolution |
| [CLI](cli.md) | Commands, execution behavior and failures |
| [Commands](commands-events.md) and [events](events.md) | Types, registration, delivery, cancellation and errors |
| [Windows](windows.md) | Window declarations, handles, child views and close behavior |
| [Capabilities](capabilities.md) | Extension installation, renderer targets and permission scopes |
| [Packaging](packaging.md) | Artifacts, platform overrides, signing and resources |
| [Diagnostics](debugging.md) | Logs, DevTools and failure classification |

[Tutorial](tutorial/index.md) contains the step-by-step exercises: minimal application, commands, events, windows, file access and the complete Todo application. Reference pages can be read independently; they do not require a tutorial project.

## Platform scope

Supported development targets are macOS Apple Silicon, Windows x64 and Linux x64. Native capability availability varies by platform. Builds and packages are produced on their target operating system.

Distributed applications include Chromium and the matching subprocess helper. Runtime size and subprocesses are part of this model; Proton does not use the system webview.

## API references

- [Application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.0/)
- [Extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.0/)
- [Typed contracts](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.0/)
- [Frontend client](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.0/)
- [Rabbita integration](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.0/)

Generated API documentation provides full signatures; these reference pages describe behavior and relationships between APIs.
