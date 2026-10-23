# proton_cli

`moonbit-community/proton_cli` creates, develops, builds, and packages Proton
desktop applications. See the repository [README](../README.md) for application
workflows and configuration.

`proton_cli new` offers a single-module `minimal` template and a full-stack
`isomorphic` template. It invokes `moon-new@0.1.0` with the selected template
from this repository's `main` branch. Pass `--template minimal|isomorphic`;
`isomorphic` is the default. Only the destination path, `--template` and `--author`
are accepted. Creation is non-interactive and does not run `moon check`.
Customize the generated configuration and application source after creation.

Direct creation is also supported, without installing the Proton CLI:

```sh
moonx moonbit-community/moon-new my-app \
  --template moonbit-community/proton --branch main \
  --subdir templates/isomorphic
```

Use `--subdir templates/minimal` for `--template minimal`, and `--user <name>`
for the CLI's `--author <name>`. The CLI remains useful for `dev`, `build` and
`package` after creation.

On Windows, `build` and `package` compile the first `.ico` in `package.icons`
into the application executable using the Windows SDK resource compiler. This
works with the default Wasm CLI; no native CLI installation is required.
`package --icon` overrides the configured icon. The Windows SDK must be
installed, as required for the application's native MoonBit build.

When debugging is enabled, Chromium selects an available CDP port by default and
prints its browser WebSocket endpoint to stderr:

```text
DevTools listening on ws://127.0.0.1:<port>/devtools/browser/<id>
```

`proton_cli dev` preserves this output. External tools should capture stderr
from process startup and wait for this line instead of reserving and releasing
a port before launch. The endpoint is announced asynchronously; a process that
exits before announcing it has not supplied a debugging endpoint.
`PROTON_REMOTE_DEBUGGING_PORT=0` explicitly selects this behavior. A fixed port
can still be requested with `PROTON_REMOTE_DEBUGGING_PORT=9333`. Remote debugging
is disabled when the application debug setting is off. This announcement does
not require enabling `PROTON_CEF_LOG`.

`dev`, `build`, `package`, and `doctor` share the typed `AppConfig` decoder.
Project paths are resolved by the CLI, without replacing the relative values
in the configuration. `dev` passes a per-launch configuration snapshot with CLI
overrides to the application; the source project file is not modified.
`package` likewise embeds the effective configuration, including CLI overrides
for the backend package, formats, and platform settings.
