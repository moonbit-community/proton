# Proton

Proton is a MoonBit framework for building native desktop applications with a
web frontend.

Supported source-built native backends:

- Windows x64
- macOS Apple Silicon
- Linux x64

## Quick start

Install the CLI and create a project:

```sh
moon install moonbit-community/proton_cli
proton_cli new my-app --yes
cd my-app
moon update
proton_cli cef setup
proton_cli dev
```

The default `isomorphic` template contains a shared command contract, a Rabbita
frontend, and a Proton backend. Use `--template minimal` for a single MoonBit
module with inline HTML:

```sh
proton_cli new my-app --template minimal --yes
```

`cef setup` installs the CEF runtime and subprocess helper required by the
current Proton release. Installations are immutable and shared by all projects
under `~/.proton/store` and `~/.proton/helpers`. Set `PROTON_RUNTIME_STORE` to
an absolute path to relocate the runtime store.

All published Proton modules use one lockstep version. The CLI, framework,
extensions, packager, code generator, and CEF setup tool must come from the same
release.

## Application entry

Applications are defined with the `App` builder. A small application can use
inline HTML:

```moonbit
async fn main {
  @proton.html(
    "Hello Proton",
    "<h1>Hello from MoonBit</h1>",
    width=900,
    height=700,
    debug=true,
  )
  .load_config()
  .run_or_abort()
}
```

Proton also supports URL, file, and packaged asset entries through
`@proton.url`, `@proton.file`, and `@proton.asset`.

An isomorphic backend registers commands defined by the shared contract:

```moonbit
async fn main {
  let backend = @todo.Backend()
  @proton.asset("My App", "frontend/dist/index.html")
  .load_config()
  .single_instance()
  .commands(fn(registrar) raise { backend.register_commands(registrar) })
  .run_or_abort()
}
```

The frontend invokes these commands through `proton_client` or the typed
Rabbita integration. It can also subscribe to events emitted by the backend.

## Capabilities

Extensions expose typed capabilities. Adding a capability installs its backend
handlers and grants access to selected renderer targets. Omitting a capability
is valid; an unavailable operation is rejected by the bridge without preventing
the application from starting.

Filesystem access must declare both allowed roots and commands:

```moonbit
@proton.html("Files", html)
.capability(
  @fs.capability([
    @fs.PermissionRoot("./workspace", [
      "read_file",
      "write_file",
      "readdir",
    ]),
  ]),
)
```

The default target is the primary window entry. Multi-window applications can
grant a capability to explicit `RendererTarget::entry` or
`RendererTarget::bundled` targets. Relative filesystem roots and requests are
anchored to `@proton.resource_dir()`.

## Application windows

Additional windows are declared with `add_window` before startup, then created
through `WindowManager::open`. `WindowHandle` provides lifecycle and native
window operations including:

- show, hide, focus, close, minimize, maximize, restore, and fullscreen
- title, size, position, centering, always-on-top, and zoom
- resizable, movable, minimizable, maximizable, opacity, and aspect ratio
- minimum and maximum size constraints
- taskbar visibility, progress, attention, and content capture protection

Window creation, state changes, and close interception are integrated with the
managed async runtime. By default the application quits after its final window
closes. Use `LastWindowClosedPolicy::KeepRunning` for tray or background
applications.

Application windows can host independent web contents views with explicit
bounds, visibility, z-order, navigation, DevTools, and lifecycle events. See
`examples/45_bridge_multi_window` and `examples/52_web_contents_view`.

Native application menus are available on macOS and Linux. Native context
menus are available on macOS, Windows, and Linux. Application menu bars are not
yet implemented on Windows.

Titlebar overlay uses `TitlebarStyle::Overlay` and is implemented on macOS and
Windows. Interactive controls inside a draggable region must use
`-webkit-app-region: no-drag`. See `examples/48_titlebar_overlay`.

The runnable examples cover the full window API, including context menus,
progress, attention, resizing, content protection, and minimize/maximize
controls. See [examples/Readme.md](examples/Readme.md).

## Project configuration

`proton.project.json` configures CLI orchestration and packaging:

```json
{
  "identifier": "com.example.my-app",
  "backend": {
    "path": ".",
    "package": "backend/app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "npm run dev -- --port 4300",
    "before_build": "npm run build",
    "dist": "dist"
  },
  "package": {
    "product_name": "My App",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "output": "dist"
  }
}
```

`identifier` is the stable application identity used by the runtime and
packaging tools. `.load_config()` reads it from the project file during
development and from packaged metadata after installation. Applications that
do not use `proton.project.json` must call
`.identifier("com.example.my-app")` instead.

`backend.path` is the exact working directory passed to Moon and
`backend.package` selects the executable package. Proton does not scan parent
directories for `moon.work`, `moon.mod`, or another project configuration.
Project paths must be relative and use `/` separators.

The frontend command is entirely project-defined; Proton does not embed Warren,
Vite, or another frontend server. `proton_cli dev` runs `before_dev`, waits for
`dev_url`, and then starts the native application. It rejects an already
occupied development endpoint before starting the configured command. Use
`--no-frontend` when the frontend is managed separately.

The Proton bridge exists only inside the CEF renderer. Opening the development
URL in a regular browser can preview the page, but native commands and events
are unavailable there.

## Build and diagnose

```sh
proton_cli build
proton_cli build -- --release
proton_cli doctor
```

`build` runs `frontend.before_build`, validates `frontend.dist`, and builds the
configured MoonBit package for the native target. Arguments after `--` are
passed to `moon build`.

`doctor` checks project configuration, the MoonBit toolchain, and the required
CEF runtime and helper without changing the project.

## Packaging

Create native artifacts with:

```sh
proton_cli package --dry-run
proton_cli package --release
```

Supported host-native formats are:

- macOS: `app`, `zip`, and `dmg`
- Windows: `app`, `zip`, and `nsis`
- Linux: `appimage`

Use repeated `--format` options or `package.formats` in
`proton.project.json`. Output is written to `dist` by default.

`package.resources` copies sidecar files into the application resources
directory. Backend code resolves the same files before and after packaging with
`@proton.resource_dir()`. `package.sign.binaries` names copied executables that
must be included in platform signing.

On macOS, `--sign` signs the application and `--notarize` submits, staples, and
validates distributable artifacts. URL schemes and document types are written
to the macOS application metadata. Current Windows and Linux packages do not
install operating-system URL or document associations.

`moonbit-community/proton_package` is also available as a generic packager for
already-built executables. It does not discover Proton projects, build source,
or assemble CEF. See [package/README.md](package/README.md).

## Runtime options

Enable operating-system single-instance routing with `.single_instance()`.
Later launches forward protocol URLs, document paths, and reopen activation to
the primary process.

Headless mode uses CEF off-screen rendering without native top-level windows:

```moonbit
@proton.html("Automation", html)
.load_config()
.headless()
.run_or_abort()
```

`PROTON_HEADLESS=1` forces the same mode for automation. Native dialogs, menus,
titlebars, and other native window operations are unavailable in headless mode.
Linux still requires an X11 display, such as Xvfb in CI.

Development and explicit debug mode use an ephemeral remote-debugging port by
default. Set `PROTON_REMOTE_DEBUGGING_PORT` to a fixed port from `1024` through
`65535` only when an external tool requires one.

## Logging

Applications use `tonyfettes/xlog` directly. Proton reserves `proton.*` log
categories; applications should use their own categories such as `app.*`.
Direct runs and `proton_cli dev` write to stderr. Packaged applications default
to platform log files. `MOON_XLOG` controls xlog filtering and
`PROTON_LOG_OUTPUT` selects `stderr` or `file`.

CEF diagnostics are disabled by default. Use `PROTON_CEF_LOG` only while
investigating browser-runtime failures.

## Documentation

- [Examples](examples/Readme.md)
- [Proton facade](proton/README.md)
- [Extensions](extensions/README.md)
- [Generic packager](package/README.md)
- [Maintainer guide](AGENTS.md)

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
