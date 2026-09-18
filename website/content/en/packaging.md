# Packaging reference

[中文](zh/packaging.html)

The Proton CLI packages a project into a distributable containing its executable, frontend assets, CEF runtime, matching helper and declared resources. A backend executable alone is not a complete distribution. Packaging targets the host platform.

## Metadata

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

## Platform overrides

Each platform object accepts `formats`, `resources` and `sign`. Windows additionally accepts `nsis_install_mode`. A platform format list replaces the shared list. Platform resources are combined with shared resources. Path values use the project configuration directory as their base.

| Platform | Formats | Default |
| --- | --- | --- |
| macOS Apple Silicon | `app`, `zip`, `dmg` | `app`, `zip` |
| Windows x64 | `app`, `zip`, `nsis` | `app`, `zip` |
| Linux x64 | `appimage` | `appimage` |

On Windows, configured ICO content is compiled into the application executable using the Windows SDK resource compiler. NSIS output additionally requires NSIS.

## NSIS installation mode

| Value | Behavior |
| --- | --- |
| `currentUser` | Default; current user, no administrator installation required |
| `perMachine` | All users, elevation required |
| `both` | Installer offers a scope choice; may prompt for elevation even for current-user installation |

Changing the mode is not an installation-scope migration. Updates to an existing machine-wide installation should retain its intended scope.

## Signing and notarization

`--release` controls build mode and does not imply signing. On macOS, `--sign` requests signing; `--notarize` requests notarization, stapling and validation using configured credentials. Available identity and credential options are listed by `proton_cli package --help`.

An unsigned or locally signed artifact does not establish a trusted publisher identity. Credentials are deployment configuration, not application source.

## Runtime resource behavior

Packaged frontend files load without the development server. Backend resource paths resolve through `resource_dir()`. Installed resources may be read-only; persistent application data belongs outside them.

`--dry-run` validates and displays the packaging plan. It does not prove that packaging, signing or the packaged runtime works. The [Todo tutorial](tutorial/isomorphic.md) includes the application build and package exercise.
