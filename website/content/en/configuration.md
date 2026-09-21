# Project configuration

[中文](zh/configuration.html)

`proton.project.json` contains application identity and CLI build/package metadata. It is a JSON object with four recognized top-level fields. Unknown fields are rejected. Window state, command registration and capabilities belong to the MoonBit application builder, not this file.

## Top-level fields

| Field | Type | Requirement / meaning |
| --- | --- | --- |
| `identifier` | string | Required, validated application identifier |
| `backend` | object | Optional at decoding; provides the CLI backend location and entry |
| `frontend` | object | Optional frontend command and asset configuration |
| `package` | object | Optional distribution metadata; required for metadata-driven packaging |

A minimal configuration shape is:

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

## Package

The full `package` field reference, platform override rules and artifact formats are documented in [packaging](packaging.md).

## Warren commands in 0.3.0

The published CLI 0.3.0 emits deprecated native `moonx` commands. The supported replacement is an installed `moonbit-community/warren@0.3.3` executable with these frontend fields:

```json
{
  "path": "frontend",
  "dev_url": "http://127.0.0.1:4300",
  "before_dev": "warren dev --browser-entry main --direct --port 4300",
  "before_build": "warren build --browser-entry main",
  "dist": "dist"
}
```

This object is the value of `frontend`, not a complete project configuration. The corrected generator is in main but not the published CLI 0.3.0. Warren 0.3.2 has no published Wasm executable; removing only the native target flag does not work. Installation requirements are listed in [environment](installation.md).
