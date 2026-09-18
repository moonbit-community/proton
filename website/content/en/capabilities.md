# Extensions and capabilities

[中文](zh/capabilities.html)

Extensions register reusable host operations. A renderer capability installs an extension's backend and grants a permission scope to selected renderer targets. Adding `proton_ext` as a module dependency only makes code available; it does not install handlers or grant access.

## Registration and targets

`App.capability(capability, targets?)` configures installation and access. With no explicit targets, the grant applies to the main entry. `RendererTarget.entry(window=...)` and `RendererTarget.bundled(window=...)` select entry or bundled-page targets for a named window. Permissions do not implicitly become global merely because windows belong to one application.

Application commands use `app:` routes; extension operations use `ext:<extension>/<operation>`. JavaScript can invoke an installed operation through `window.__MoonBit__.core.invokeOp(route, request)`, which returns a promise.

## Filesystem scope

`proton_ext/fs.capability` accepts `PermissionRoot` values pairing a host directory with permitted operations. The scope is configured by the backend; renderer requests cannot widen it.

| Property | Behavior |
| --- | --- |
| Relative root or request path | Resolved against `resource_dir()` |
| Path outside allowed roots | Rejected, including symlink escapes |
| Operation absent from root grant | Not authorized by that grant |
| Text payloads | UTF-8 |

Supported filesystem operation names include `read_file`, `write_file`, `mkdir`, `readdir`, `remove`, `rmdir`, `rename`, `realpath`, `exists`, `kind` and `size`. Canonical path checks and operations are serialized within the extension.

## Availability and errors

A missing capability leaves its route unavailable. An installed extension can still reject a request because of scope, invalid arguments, a platform limitation or an operating-system failure. These failures are reported through the command bridge; installation does not imply that every native operation will succeed.

Filesystem, dialogs, clipboard, shell, tray and other capabilities have different scope types and platform coverage. The notification extension in 0.3.0 targets macOS. Framework platform support is not a capability support matrix.

Complete builders and request/response types are in the [extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.0/). A complete exercise is in the [file access tutorial](tutorial/capabilities.md).
