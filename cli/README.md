# proton_cli

`moonbit-community/proton_cli` creates, develops, builds, and packages Proton
desktop applications. See the repository [README](../README.md) for application
workflows and configuration.

`proton_cli new` offers a single-module `minimal` template and a full-stack
`isomorphic` template. Select one interactively or pass
`--template minimal|isomorphic`; `isomorphic` is the non-interactive default.

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
