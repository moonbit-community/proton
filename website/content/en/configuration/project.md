# Project configuration

`proton.project.json` contains application identity and CLI build/package metadata. It is a JSON object with five recognized top-level fields. Unknown fields are rejected. Window state, command registration and capabilities belong to the MoonBit application builder, not this file.

The default filename is `proton.project.json`. To use another filename such as `moon.proton.json`, pass `--config moon.proton.json` to `dev`, `build` or `package`; it is not an automatically discovered alias.

The root platform-override format below requires Proton 0.7.0; see the migration
section when upgrading from 0.6.0.

## Top-level fields

| Field | Type | Requirement / meaning |
| --- | --- | --- |
| `identifier` | string | Required, validated application identifier |
| `backend` | object | Optional at decoding; provides the CLI backend location and entry |
| `frontend` | object | Optional frontend command and asset configuration |
| `package` | object | Optional distribution metadata; required for metadata-driven packaging |
| `platforms` | object | Optional host overrides: `macos`, `windows`, `linux` |

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

Backend/frontend paths, package icons, package resources and package output are resolved from the configuration directory. `frontend.dist` is resolved from the frontend directory. Absolute paths remain absolute. Path separators follow the host operating system. Loading configuration preserves path strings and does not require referenced files or directories to exist; build and packaging operations check the inputs they use.

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
| `sign.binaries` | string array | Empty; additional binaries selected for signing, or macOS `dir/**` trees |
| `url_schemes` | string array | Empty; registered application URL schemes |
| `document_types` | object array | Empty; document associations |
| `output` | string | `dist`, relative to configuration directory |

A document type contains required `name` and `extensions`; `role` defaults to `Viewer`. The canonical identifier is the top-level `identifier`, not a package field. Changing the product name does not change application identity.

For automatic updates, `package.version` is also the release ordering value. It must use three non-negative `Int32` components without leading zeros or suffixes, and each update must strictly increase it. `package --version` overrides that value consistently in the packaged application and update metadata. There is no `revision` field. See [update metadata](../command-line-interface/packaging.md#update-artifacts-and-metadata).

## `package.sign`

| Field | Type | Default / meaning |
| --- | --- | --- |
| `binaries` | string array | `[]`; additional binaries to sign, relative to the configuration directory |

An entry is an exact target that must exist in the package, and an `.app` or `.framework` directory is signed as one target. On macOS, an entry ending in `/**` is a tree: at packaging time Proton signs every Mach-O executable, library and bundle under that packaged directory, inside out, and skips symlinks and object files. Other glob patterns are rejected. Trees are macOS-only: Windows signs each listed file with `signtool`, so a signed Windows package fails on a tree. Put trees under `platforms.macos.package.sign` when the configuration also signs for Windows.

Omitting `sign` adds no extra binaries. This object does not enable signing: use `package --sign` or `--notarize`.

## `package.document_types[]`

| Field | Type | Default / meaning |
| --- | --- | --- |
| `name` | string | Required document type display name |
| `extensions` | string array | Required nonempty list of file extensions |
| `role` | string | `Viewer`; document role passed to packaging |

## Platform overrides

Root `platforms` is the only platform-override location. Each `macos`, `windows`,
or `linux` object may contain partial `backend`, `frontend`, and `package`
sections. The platform is the operating system running the CLI, not the MoonBit
compilation target. No additional configuration files are loaded.

Resolution order is common fields, host-platform overrides, then explicit CLI
options. Defaults apply to omitted effective fields; validation checks every
platform section, including inactive platforms. Unknown fields are errors.

- Omitted fields inherit the common value.
- Objects override their individual fields; arrays replace the entire common
  array, including `resources` and `sign.binaries`. There is no append step.
- Explicit `null` clears optional fields such as `before_build`, `prepare`, or
  `sign`. Required fields and arrays cannot be set to `null`.
- `identifier` and `package.version` are shared across platforms and cannot be
  overridden. Nested `platforms` objects are not supported.
- An empty effective `formats` list selects the host's default formats.

The platform-specific package fields are:

| Field | Type | Default / meaning |
| --- | --- | --- |
| `platforms.macos.package.minimum_system_version` | string | Unset; `major.minor[.patch]`, written to `LSMinimumSystemVersion`. Does not change compilation targets or validate binary compatibility |
| `platforms.windows.package.nsis_install_mode` | string | `currentUser`; accepts `currentUser`, `perMachine`, or `both` |

All other package overrides use the common package field names, except `version`.
Platform-specific fields are rejected outside their respective platform.
See [packaging behavior](../command-line-interface/packaging.md).

## Command working directories

`frontend.path` is the working directory of both frontend commands. If omitted,
they run from the configuration directory. `package.prepare` always runs from
the configuration directory. Commands remain shell strings: Windows uses
`cmd /d /c`, macOS/Linux use `sh -c`. They inherit the CLI process environment;
Proton does not add project tool directories to `PATH`.

Paths inside a command are interpreted by that shell from its working directory.
For a project-level `tools/warren` next to `frontend/`, use `../tools/warren build`
with `frontend.path: "frontend"`; on Windows override it with
`..\\tools\\warren.exe build` in JSON. The executable and its arguments must
follow the host shell's syntax. `--frontend-path` overrides the frontend working
directory; `--command` replaces only the development command, keeping that
working directory. Changing the working directory also changes the base for
`frontend.dist`; it does not change package resource or output path bases.

## Migration from 0.6.0

In 0.7.0, move `package.platforms.<platform>.*` to
`platforms.<platform>.package.*`. Old locations produce a migration error.
Previously, platform resources and signing inputs were appended to common
arrays; now list the complete desired array in an override.

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

These directories hold generated artifacts determined by source, build commands and project configuration. The runtime and subprocess executable installed by setup live in shared user-level storage, outside the application source tree.

## Complete configuration example

The paths below are illustrative: referenced icons, resources and commands must exist in the application project.

```json
{
  "identifier": "com.example.notes",
  "backend": {
    "path": "backend",
    "package": "app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "../tools/warren dev --browser-entry main --direct --port 4300",
    "before_build": "../tools/warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Notes",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "icons": ["icons/app.icns", "icons/app.ico", "icons/app.png"],
    "prepare": "node scripts/prepare.mjs",
    "resources": ["resources"],
    "sign": {
      "binaries": []
    },
    "url_schemes": ["notes"],
    "document_types": [
      {
        "name": "Note",
        "extensions": ["note"],
        "role": "Editor"
      }
    ],
    "output": "dist"
  },
  "platforms": {
    "macos": {
      "package": {
        "formats": ["app", "dmg"]
      }
    },
    "windows": {
      "package": {
        "formats": ["nsis"],
        "nsis_install_mode": "currentUser"
      },
      "frontend": {
        "before_dev": "..\\tools\\warren.exe dev --browser-entry main --direct --port 4300",
        "before_build": "..\\tools\\warren.exe build --browser-entry main"
      }
    },
    "linux": {
      "package": {
        "formats": ["appimage"]
      }
    }
  }
}
```

## Runtime configuration

Load configuration independently, then install it on the application:

```moonbit
let config = @proton.load_config()
let app = @proton.html("Hello", "<h1>Hello</h1>")..config(config)

if config.frontend is Some(frontend) {
  if frontend.dev_url is Some(url) {
    println(url)
  }
}
```

`load_config()` resolves host-platform overrides and returns the effective typed
`AppConfig`, raising
`AppConfigError` immediately on failure. Development uses `proton.project.json`;
packaged applications use `proton-package.json`. For an explicit file path, use
`@proton.AppConfig::load(path)`. Applications can also construct `AppConfig` directly.

Read fields from the configuration value. Nested sections are optional structs:
`config.frontend` contains `dev_url`, `path`, `dist`, `before_dev`, and
`before_build`. The effective `package_config` also exposes
`minimum_system_version` and `nsis_install_mode`. Unselected platform definitions
are not retained in `AppConfig`; `to_json()` writes a reusable effective snapshot.
JSON `package` maps to `config.package_config`; JSON
`backend.package` maps to the backend's `app_package` field.

`proton_cli dev` supplies the effective configuration after `--url`, `--command`,
`--frontend-path`, and `--package` overrides. Packaging likewise embeds the
effective configuration, including CLI overrides for formats and platform settings.
Relative paths retain their spelling; reading a field does not resolve paths
or execute commands.

`app..config(config)` installs an independent copy and is mutually exclusive with
`app..identifier(...)`. Invalid configuration or a mismatch with the packaged
identity prevents startup. Retain `config` to inspect it; there is no application
configuration getter. `app.name()` and `app.version()` read the installed snapshot
without further file I/O.
