# Packaging reference

The Proton CLI packages a project into a distributable containing its executable, frontend assets, CEF runtime, matching helper and declared resources. A backend executable alone is not a complete distribution. Packaging targets the host platform.

Field types and defaults are defined in [Configuration](../configuration/project.md).

## Platform overrides

Each platform object accepts `formats`, `resources` and `sign`. Windows additionally accepts `nsis_install_mode`; macOS accepts `minimum_system_version`. A platform format list replaces the shared list. Platform resources are combined with shared resources. Path values use the project configuration directory as their base.

| Platform | Formats | Default |
| --- | --- | --- |
| macOS Apple Silicon | `app`, `zip`, `dmg` | `app`, `zip` |
| Windows x64 | `app`, `zip`, `nsis` | `app`, `zip` |
| Linux x64 | `appimage` | `appimage` |

## Icon and tool prerequisites

| Artifact | Icon and tooling |
| --- | --- |
| macOS app / zip | ICNS for the application icon; native Apple tooling for builds and signing |
| macOS dmg | Uses system hdiutil to create an image from the app |
| Windows app / zip | Windows SDK rc.exe embeds ICO into the EXE; PNG is not automatically converted |
| Windows nsis | Also requires NSIS makensis |
| Linux appimage | Requires a PNG icon and executable appimagetool on PATH |

The default scaffold does not provide icons. On Linux, missing PNG validation fails before invoking AppImage tooling. See the [Todo packaging steps](../tutorial/isomorphic.md#linux) for preparation. Supply the platform's icon format rather than expecting Windows to convert icons intended for other platforms.

## NSIS installation mode

| Value | Behavior |
| --- | --- |
| `currentUser` | Default; current user, no administrator installation required; installs under `%LOCALAPPDATA%` with current-user registration |
| `perMachine` | All users, elevation required; installs under Program Files with machine-wide registration |
| `both` | Installer offers a scope choice; may prompt for elevation even for current-user installation |

Changing the mode is not an installation-scope migration. Updates to an existing machine-wide installation should retain its intended scope.

**Upgrading older Proton installers:** older Proton releases always generated machine-wide NSIS installers. Applications distributed that way must explicitly set `package.platforms.windows.nsis_install_mode` to `perMachine` in subsequent releases. The current `currentUser` default targets a different installation scope. Existing installation paths are reused within the selected scope; fixed modes do not move installations between scopes.

`both` uses NSIS MultiUser and requests the highest available privileges. Its scope selector can therefore follow a UAC prompt even when the user chooses a per-user installation. `--nsis-install-mode` overrides the project setting; see the [CLI reference](commands.md#package).

## Minimum macOS version

minimum_system_version only writes macOS LSMinimumSystemVersion metadata. It does not make a binary built against a newer SDK/CEF compatible with older systems. Validate the complete artifact on the minimum supported OS; compilation alone is insufficient.

## Signing and notarization

`--release` controls build mode and does not imply signing. On macOS, `--sign` requests signing; `--notarize` requests notarization, stapling and validation using configured credentials. Identity and credential environment variables are listed in the [CLI reference](commands.md#signing-environment).

An unsigned or locally signed artifact does not establish a trusted publisher identity. Credentials are deployment configuration, not application source.

## Runtime resource behavior

Packaged frontend files load without the development server. Backend resource paths resolve through `resource_dir()`. Installed resources may be read-only; persistent application data belongs outside them.

`package.resources` supplies shared sidecar files; platform-specific resources are appended. `package.sign.binaries` and its platform override select additional executables for signing. Explicit CLI options take precedence over configuration. Field types and merge rules are listed in [Configuration](../configuration/project.md#package).

`--dry-run` validates and displays the packaging plan. It does not prove that packaging, signing or the packaged runtime works. The [Todo tutorial](../tutorial/isomorphic.md) includes the application build and package exercise.

## Package preparation

`package.prepare` runs once from the project configuration directory after the frontend and native executable have been built, before resources are assembled. Use it to generate declared package-only resources or additional binaries. A nonzero exit stops packaging.

`proton_cli build` and `proton_cli package --dry-run` do not execute this hook. The standalone `proton_package` tool packages already-built executables and supplied payloads; it does not discover projects, run build/preparation commands or assemble CEF. See the [standalone packager](https://github.com/moonbit-community/proton/blob/18915e6b3c852b760dee6550f066f46d95a1248d/package/README.md).

## Update artifacts and metadata

Updater metadata is optional. `package --updater-base-url <https-url> --updater-published-at <instant>` requires both options and uses the effective `package.version` (including a `--version` override). There is no separate update revision.

| Host | Required output format | Selected self-update artifact |
| --- | --- | --- |
| macOS | `zip` | `.app.zip`; a DMG is not an automatic-update payload |
| Windows | `nsis` | `-setup.exe`; an app directory or ZIP is not an installer |
| Linux | `appimage` | `.AppImage` |

If the selected packaging formats do not produce that artifact, metadata generation fails. It does not turn another format into an update payload.

The command writes `<artifact>.sha256` and `latest-<platform>.json` beside the artifacts. The JSON is a schema 3 **fragment**, not a ready-to-publish channel: the artifact signature is intentionally empty. Its fields are:

| Field | Contract |
| --- | --- |
| `schema_version` | `3`; schema 2 is not accepted by the new updater |
| `version` | Effective application version, exactly `major.minor.patch`; numeric comparison, no leading zeros or suffixes |
| `published_at` | UTC `YYYY-MM-DDTHH:MM:SSZ` |
| `notes_url` | Optional release-notes URL when assembling the final manifest |
| `platforms` | Entries keyed by `darwin-arm64`, `win32-x64`, or `linux-x64` |
| `platforms.<id>.kind` | `full` |
| `platforms.<id>.url` | HTTPS artifact URL built from the base URL and filename |
| `platforms.<id>.size` | Positive `Int64` byte count |
| `platforms.<id>.sha256` | Lowercase hexadecimal SHA-256 digest |
| `platforms.<id>.signature` | Lowercase hexadecimal RSA/SHA-256 artifact signature |

The publisher signs the artifact with its own private key and fills in `signature`. Platform entries for the same application version can be assembled into one manifest. Sign the final manifest bytes too: the runtime fetches the configured endpoint and `<endpoint>.sig`, where the latter contains the detached RSA/SHA-256 signature as hexadecimal text. Editing the manifest after signing invalidates that signature. Publish the artifacts, complete manifest and detached signature together over HTTPS.

`--sign` / `--notarize` sign operating-system distributions; they do not fill in updater signatures. Proton neither accepts a private signing key through these updater options nor uploads files. Public-key generation/import and the installation lifecycle are documented under [Application updates](../introduction/application-api.md#application-updates).

## URL schemes and document types

`package.url_schemes` and `package.document_types` describe operating-system launch associations. Their effects depend on the artifact:

| Artifact | Behavior |
| --- | --- |
| macOS app | Writes URL schemes and document types into application metadata |
| Windows NSIS | Registers URL schemes in the selected installation scope and removes owned registrations on uninstall; document-type associations are not implemented |
| Windows app / zip | Does not install operating-system associations |
| Linux AppImage | Declares URL schemes in the bundled desktop entry; desktop integration is still needed to register it with the system. Document-type associations are not implemented |

Declaring an association does not implement application handling. Register launch-input handlers as described in [application lifecycle](../introduction/application-api.md#application-lifecycle).
