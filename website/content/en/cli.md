# CLI reference

[中文](zh/cli.html)

`proton_cli` operates on a Proton project described by `proton.project.json`. `-C <directory>` selects the project directory. Command-specific options are listed by `proton_cli <command> --help`.

## Commands

| Command | Behavior |
| --- | --- |
| `new <name>` | Creates a project; supports `minimal` and `isomorphic` templates |
| `cef setup` | Installs the release-matched runtime and helper |
| `doctor` | Read-only project/environment diagnostics |
| `dev` | Manages frontend development when configured, builds and launches the native backend |
| `build` | Builds configured frontend assets and the native backend |
| `package` | Builds and assembles platform distribution artifacts |

## Project creation

`--template minimal` creates one native module with inline HTML. `--template isomorphic` creates shared, frontend and backend modules. The non-interactive default is `isomorphic`. `--yes` accepts defaults; `--identifier` sets application identity; `--no-git` disables Git initialization.

The current published CLI is 0.3.0. Its generated Warren commands need the replacement documented in [project configuration](configuration.md). Installing Warren alone does not change previously generated configuration files.

## Development

When configured, `dev` launches `frontend.before_dev` in `frontend.path`, waits for the development URL, then runs the native application using that URL. An occupied endpoint is rejected for a CLI-managed frontend. `--no-frontend` selects an externally managed server. `--command` and `--frontend-path` override the frontend command and directory; `--setup` permits runtime setup as part of development.

Frontend refresh is owned by the frontend tool. Backend source changes require rebuilding/restarting the native application. The CLI manages the frontend process it starts; an externally managed server has a separate lifetime.

## Build

The build sequence is frontend command, frontend-output validation, then native backend build. A frontend command failure prevents the backend build from proceeding. `build` does not produce a complete distribution bundle.

Arguments after `--` are forwarded to Moon, for example `proton_cli build -- --release`. The backend target is always native; overriding `--target` through forwarded arguments is rejected.

## Package

`package --release` selects release output. `--dry-run` reports the plan without executing the full build/packaging/signing flow. Repeated `--format` flags select artifact formats. `--icon` overrides configured icons. Signing and notarization options are separate from build mode. See [packaging](packaging.md).
