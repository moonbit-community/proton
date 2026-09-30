# Application API reference

The root `moonbit-community/proton` package is the public application facade. Use the builder before `run`; use context and handle operations while the application is running. CLI project metadata does not replace runtime configuration.

| Area | Owner / entry | Reference |
| --- | --- | --- |
| Startup, readiness, quit, task cleanup | `App`, `ApplicationContext`, lifecycle hooks | [Lifecycle](lifecycle.md) |
| Window declarations, instances, child browsers | `App`, `WindowManager`, `WindowHandle`, `ViewHandle` | [Windows](windows.md) |
| Request/response communication | contract, registrar, client | [Commands](commands-events.md) |
| Frontend notifications and subscription lifetime | emitters, client subscriptions | [Events](events.md) |
| Host operations and renderer authorization | `App.capability`, extension-specific scope | [Capabilities](capabilities.md) |
| Cookies, browser storage, proxy | `SessionHandle`, startup builder | [Browser sessions](sessions.md) |
| Signed application updates | `App.update_channel`, `PendingUpdate` | [Updates](updates.md) |
| Process ownership and activation | single-instance builder, context methods | [Process control](process-control.md) |
| Menus, language, background residency | window/application configuration | [Selected examples](../examples/01_run.md) |
| Paths, files and build metadata | project configuration and application paths | [Project structure](project-structure.md), [Configuration](../configuration/project.md) |

For the complete set of methods, overloads, typed errors and defaults, use the [versioned API index](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/). The pages here specify relationships and behavior; they do not reproduce every signature. A short code fragment in a reference page is illustrative, not an instruction to modify a tutorial project.
