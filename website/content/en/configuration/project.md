# Project configuration

`proton.project.json` contains application identity and CLI build/package metadata. It is a JSON object with four recognized top-level fields. Unknown fields are rejected. Window state, command registration and capabilities belong to the MoonBit application builder, not this file.

The default filename is `proton.project.json`. To use another filename such as `moon.proton.json`, pass `--config moon.proton.json` to `dev`, `build` or `package`; it is not an automatically discovered alias.

## Top-level fields

| Field | Type | Requirement / meaning |
| --- | --- | --- |
| `identifier` | string | Required, validated application identifier |
| `backend` | object | Optional at decoding; provides the CLI backend location and entry |
| `frontend` | object | Optional frontend command and asset configuration |
| `package` | object | Optional distribution metadata; required for metadata-driven packaging |

`identifier` is trimmed and must have at least two nonempty dot-separated components. Each component starts with an ASCII letter or digit and contains only ASCII letters, digits or hyphens.

A minimal configuration is:

```json
{
  "identifier": "com.example.app",
  "backend": { "path": ".", "package": "app" }
}
```

## Backend

When `backend` is present, both fields are required.

| Field | Type | Interpretation |
| --- | --- | --- |
| `path` | string | Directory, resolved relative to the configuration directory |
| `package` | string | Moon package selector used from that directory |

## Frontend

All frontend fields are optional at decoding. Individual CLI commands impose additional requirements.

| Field | Type | Default / interpretation |
| --- | --- | --- |
| `path` | string | Configuration directory if omitted; command working directory |
| `dev_url` | string | No default; development page URL |
| `before_dev` | string | No default; frontend server command |
| `before_build` | string | No default; frontend build command |
| `dist` | string | No default; output directory, relative to `frontend.path` when specified |

`dev` requires a frontend command when it manages a configured development URL. `--no-frontend` connects to an externally managed server. `build` runs the configured build command before validating the frontend output and building the backend. An existing occupied development endpoint is rejected when the CLI is responsible for starting its server.

## Paths and resources

Backend/frontend paths, package icons, package resources and package output are resolved from the configuration directory. `frontend.dist` is resolved from the frontend directory. Absolute paths remain absolute.

`@proton.resource_dir()` is the application resource base: the CLI supplies the project root in development; packaged applications use their resources directory; direct runs without managed metadata use the startup working directory. Installed resources are not a persistent writable data store.

## `package`

These fields belong to the `package` object in `proton.project.json`.

| Field | Type | Default / meaning |
| --- | --- | --- |
| `product_name` | string | Required display name |
| `version` | string | Required application version; independent of Proton's version |
| `formats` | string array | Host defaults when omitted |
| `icons` | string array | Empty; icon paths relative to configuration directory |
| `prepare` | string | Absent; preparation command |
| `resources` | string array | Empty; additional packaged resources |
| `sign.binaries` | string array | Empty; additional binaries selected for signing |
| `url_schemes` | string array | Empty; registered application URL schemes |
| `document_types` | object array | Empty; document associations |
| `output` | string | `dist`, relative to configuration directory |
| `platforms` | object | Optional `macos`, `windows`, `linux` overrides |

A document type contains required `name` and `extensions`; `role` defaults to `Viewer`. The canonical identifier is the top-level `identifier`, not a package field. Changing the product name does not change application identity.

## `package.sign`

| Field | Type | Default / meaning |
| --- | --- | --- |
| `binaries` | string array | `[]`; additional binaries to sign, relative to the configuration directory |

Omitting `sign` adds no extra binaries. This object does not enable signing: use `package --sign` or `--notarize`.

## `package.document_types[]`

| Field | Type | Default / meaning |
| --- | --- | --- |
| `name` | string | Required document type display name |
| `extensions` | string array | Required nonempty list of file extensions |
| `role` | string | `Viewer`; document role passed to packaging |

## `package.platforms`

| Field | Type | Default / meaning |
| --- | --- | --- |
| `macos` | object | Absent; macOS overrides |
| `windows` | object | Absent; Windows overrides |
| `linux` | object | Absent; Linux overrides |

Each platform object accepts the following fields. Unknown fields are rejected, including `nsis_install_mode` outside Windows.

| Field | Type | Default / meaning |
| --- | --- | --- |
| `formats` | string array | Shared `package.formats`; an explicit list replaces it |
| `resources` | string array | `[]`; appended to shared resources, duplicates removed |
| `sign` | object | Absent; accepts only `binaries` (string array, default `[]`), appended to shared signing inputs with duplicates removed |
| `nsis_install_mode` | string | Windows only; `currentUser` (default), `perMachine`, or `both` |
| `minimum_system_version` | string | macOS only; `major.minor[.patch]`. Sets `LSMinimumSystemVersion`; omitted when unset. Does not change compilation targets or validate binary compatibility. |

If the resolved format list is empty, the host default formats apply. CLI options override the resolved configuration. See [packaging behavior](../command-line-interface/packaging.md) for supported formats, signing and installation modes.

## Configuration ownership and directory layout

Proton does not require the directory layout of either scaffold template. The CLI locates the backend, frontend and resources through this file; see the path resolution rules under Paths and resources below.

| File or entry | Responsibility |
| --- | --- |
| moon.mod | Module name and versioned dependencies |
| moon.pkg | Package imports, targets and executable entry declarations |
| moon.work (when using multiple modules) | Groups modules into a workspace |
| proton.project.json | Application identity, CLI build paths and packaging metadata |
| MoonBit App builder | Windows, commands, capabilities and lifecycle behavior |

A module dependency makes a module available; a package import selects the APIs used by that package. backend.package selects the build entry and does not replace Moon's package declarations.

## Build output

Moon writes build artifacts under _build/ by default. Frontend output depends on the frontend build tool and should correspond to frontend.dist. frontend/dist is an isomorphic template choice, not a fixed framework path. The packager writes distributables to package.output, which defaults to dist.

These directories hold generated artifacts determined by source, build commands and project configuration. The runtime and helper installed by setup live in shared user-level storage, outside the application source tree.

## Complete configuration example

The paths below are illustrative: referenced icons, resources and commands must exist in the application project.

```json
{
  "identifier": "com.example.notes",
  "backend": { "path": "backend", "package": "app" },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "warren dev --browser-entry main --direct --port 4300",
    "before_build": "warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Notes",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "icons": ["icons/app.icns", "icons/app.ico", "icons/app.png"],
    "prepare": "node scripts/prepare.mjs",
    "resources": ["resources"],
    "sign": { "binaries": [] },
    "url_schemes": ["notes"],
    "document_types": [
      { "name": "Note", "extensions": ["note"], "role": "Editor" }
    ],
    "output": "dist",
    "platforms": {
      "macos": { "formats": ["app", "dmg"] },
      "windows": { "formats": ["nsis"], "nsis_install_mode": "currentUser" },
      "linux": { "formats": ["appimage"] }
    }
  }
}
```

## Runtime configuration

`App::load_config()` loads this complete configuration once. `App::config()`
returns an `AppConfig` snapshot; nested sections are typed optional structs.
For example, `config.frontend` exposes `dev_url`, `path`, `dist`, `before_dev`,
and `before_build`. JSON `package` maps to `config.package_config`; JSON
`backend.package` maps to `config.backend`'s `app_package` field.

`proton_cli dev` passes the effective configuration after `--url`, `--command`,
`--frontend-path`, and `--package` overrides. Packaged applications load the full
configuration from `proton-package.json`. Relative paths remain relative in
both environments. Reading a field does not resolve a path or run a command.
`name()` and `version()` use the same snapshot and perform no further file I/O.

Applications may provide `AppConfig` directly with `with_config(config)`.
Missing or invalid configuration raises `AppConfigError` from `config()`;
builder configuration errors also prevent `run()` from starting the runtime.
