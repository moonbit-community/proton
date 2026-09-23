# Packaging reference

The Proton CLI packages a project into a distributable containing its executable, frontend assets, CEF runtime, matching helper and declared resources. A backend executable alone is not a complete distribution. Packaging targets the host platform.

Field types and defaults are defined in [Configuration](../configuration/index.md).

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

`--release` controls build mode and does not imply signing. On macOS, `--sign` requests signing; `--notarize` requests notarization, stapling and validation using configured credentials. Identity and credential environment variables are listed in the [CLI reference](index.md#signing-environment).

An unsigned or locally signed artifact does not establish a trusted publisher identity. Credentials are deployment configuration, not application source.

## Runtime resource behavior

Packaged frontend files load without the development server. Backend resource paths resolve through `resource_dir()`. Installed resources may be read-only; persistent application data belongs outside them.

`--dry-run` validates and displays the packaging plan. It does not prove that packaging, signing or the packaged runtime works. The [Todo tutorial](../tutorial/isomorphic.md) includes the application build and package exercise.
