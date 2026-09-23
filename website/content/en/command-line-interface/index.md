# Command Line Interface

This page lists every `proton_cli` command and its options. Application IPC commands are documented separately in [Commands](../introduction/commands-events.md). Configuration file fields are defined in [project configuration](../configuration/index.md).

## Invocation and global options

```text
proton_cli [--cwd <directory>] <command> [options]
```

| Option | Meaning |
| --- | --- |
| `-C`, `--cwd <directory>` | Working directory; default `.`; available to subcommands |
| `-h`, `--help` | Help for the selected command |
| `-V`, `--version` | CLI version; equivalent in purpose to `version` |

`--config`, `--moon-target-dir` and the doctor report path are resolved from the selected working directory. `dev --frontend-path` and package icon/output paths are resolved from the project configuration directory. Paths in a project configuration are resolved from that file; `frontend.dist` uses the frontend directory. Explicit command options override the corresponding configuration values.

## Command index

| Command | Purpose |
| --- | --- |
| [`help`](#help) | Show command help |
| [`version`](#version) | Print CLI version |
| [`new`](#new) | Create an application project |
| [`dev`](#dev) | Build and run an application in development mode |
| [`build`](#build) | Build frontend assets and the native backend |
| [`package`](#package) | Build and assemble distribution artifacts |
| [`doctor`](#doctor) | Report environment and project diagnostics |
| [`cef setup`](#cef-setup) | Install the release-matched runtime and helper |
| [`cef requirements`](#cef-requirements) | Print the embedded CEF requirement |
| [`updater public-key`](#updater-public-key) | Validate and format a trusted updater public key |

## `help`

```text
proton_cli help [command] [subcommand]
```

Displays help without executing the selected command. For example, `proton_cli help cef setup` describes runtime installation; it does not install anything. `proton_cli <command> --help` is the equivalent option form.

## `version`

```text
proton_cli version
```

Prints `proton_cli <version>`. It accepts no command-specific options and does not perform the update check.

## `new`

```text
proton_cli new [path] [options]
```

Creates project source files. Without `--yes`, interactive prompts are used outside CI. The defaults below apply when no prompt or explicit option overrides them.

| Argument / option | Default and meaning |
| --- | --- |
| `[path]` | `todo`; destination directory |
| `--template <name>` | `isomorphic`; accepts `minimal` or `isomorphic` |
| `--title <text>` | Derived from the project directory name; application/window title |
| `--author <name>` | `username`; MoonBit module author |
| `--identifier <id>` | `dev.proton.<normalized-project-name>`; reverse-DNS application identifier |
| `--width <pixels>` | `960`; positive integer |
| `--height <pixels>` | `640`; positive integer |
| `--check`, `--no-check` | Check enabled by default; runs `moon check --target js,native` after creation |
| `--git`, `--no-git` | Explicitly enable/disable Git initialization; non-interactive default does not initialize Git |
| `-y`, `--yes` | Skip prompts and accept defaults |
| `--dry-run` | Print planned files without writing them |

`minimal` creates a native module with inline HTML. `isomorphic` creates shared, frontend and backend modules. Invalid identifiers, nonpositive dimensions and unsupported template names are rejected.


## `dev`

```text
proton_cli dev [options] [-- <application-arguments>...]
```

Builds and runs the native backend. When a frontend command is configured, it starts that command, waits for readiness and supplies the development URL to the application. Backend changes require a rebuild/restart; frontend refresh is owned by the frontend tool.

| Option | Default and meaning |
| --- | --- |
| `--config <path>` | Project configuration; defaults to `proton.project.json` in the working directory |
| `--package <selector>` | Overrides the configured backend package; fallback `app` |
| `--moon-target-dir <path>` | Override the internal Moon invocation's output directory |
| `--url <url>` | Override `frontend.dev_url` |
| `--command <command>` | Override `frontend.before_dev` |
| `--frontend-path <path>` | Override the frontend command's working directory |
| `--timeout-ms <milliseconds>` | `30000`; frontend readiness timeout |
| `--ready-path <path>` | Use an HTTP readiness probe at this path; otherwise checks TCP connectivity |
| `--no-frontend` | Do not start a frontend command; use an externally managed server |
| `--setup`, `--no-setup` | Automatic installation of missing runtime/helper; disabled by default |
| `-- <arguments>...` | Arguments for the application, not for Moon |

A CLI-managed frontend requires a command and rejects an already occupied development endpoint. HTTP probing requires `curl`. A readiness timeout prevents application launch. The CLI owns the frontend process it starts; an external server has a separate lifetime.

## `build`

```text
proton_cli build [options] [-- <moon-build-arguments>...]
```

Runs the configured frontend build, validates frontend output, then builds the native backend. A failed frontend command prevents the backend build. The result is build output, not a complete distribution.

| Option | Default and meaning |
| --- | --- |
| `--config <path>` | Project configuration; defaults to `proton.project.json` in the working directory |
| `--package <selector>` | Overrides the configured backend package; fallback `app` |
| `--moon-target-dir <path>` | Override the internal Moon build's output directory |
| `--no-frontend` | Skip the frontend build command; does not generate missing frontend assets |
| `-- <arguments>...` | Forward to `moon build`, e.g. `-- --release` |

The backend target is always native. A forwarded `--target` override is rejected.

## `package`

```text
proton_cli package [options]
```

Builds and assembles the application, frontend assets, CEF runtime, matching helper and declared resources for the host platform. A project configuration is required. This command does not accept trailing Moon arguments.

| Option | Default and meaning |
| --- | --- |
| `--config <path>` | Project configuration; defaults to `proton.project.json` |
| `--package <selector>` | Override backend package |
| `--release` | Use release build output; otherwise debug |
| `--dry-run` | Resolve and print the plan without executing the full build/package flow |
| `--product-name <name>` | Override `package.product_name` |
| `--version <version>` | Override application version; does not select a Proton version |
| `--format <format>` | Repeatable; `app`, `zip`, `dmg`, `nsis`, `appimage`, subject to host support |
| `--output <directory>` | Override output directory |
| `--icon <path>` | Repeatable; override configured icons |
| `--url-scheme <scheme>` | Repeatable; override configured URL schemes |
| `--nsis-install-mode <mode>` | `currentUser`, `perMachine` or `both`; overrides Windows configuration |
| `--sign` | Sign the application; disabled by default |
| `--notarize` | macOS signing, notarization and stapling; implies `--sign` |
| `--updater-base-url <https-url>` | Emit update metadata using this artifact base URL; requires publication instant and revision |
| `--updater-published-at <instant>` | Publication instant in `YYYY-MM-DDTHH:MM:SSZ`; requires base URL |
| `--updater-revision <integer>` | Monotonic release sequence embedded in the app and update metadata |

CLI lists such as `--format` override configured lists. Application identity comes from the top-level configuration `identifier`; `package` has no `--identifier` option. `--release` does not imply signing. A successful dry run does not verify artifact creation or runtime behavior. See [packaging](packaging.md) for platform formats, configuration defaults and resource rules.

### Signing environment

Credentials are environment configuration, not command options.

| Variable | Meaning |
| --- | --- |
| `PROTON_MACOS_SIGNING_IDENTITY` | Required identity for macOS signing |
| `PROTON_MACOS_ENTITLEMENTS` | Optional entitlements file |
| `PROTON_MACOS_NOTARY_PROFILE` | macOS notary credential profile; `PROTON_NOTARY_PROFILE` is the fallback |
| `PROTON_MACOS_BUILD_NUMBER` | Optional bundle version override; one to three numeric components |
| `PROTON_MACOS_ALLOW_ADHOC` | `1` permits ad-hoc signing for local diagnostics |
| `PROTON_WINDOWS_CERTIFICATE` | Required certificate path for Windows signing |
| `PROTON_WINDOWS_CERTIFICATE_PASSWORD` | Certificate password; defaults to empty |
| `PROTON_WINDOWS_TIMESTAMP_URL` | Timestamp service; defaults to `http://timestamp.digicert.com`; `none` disables it |

## `doctor`

```text
proton_cli doctor [options]
```

Inspects the environment and current project without installing dependencies or repairing project files. It returns failure when diagnostics fail.

| Option | Meaning |
| --- | --- |
| `--verbose` | Include detailed project diagnostics |
| `--json` | Render one JSON document; conflicts with `--quiet` |
| `--quiet` | Render only failing diagnostics; conflicts with `--json` |
| `--output <path>` | Write the report to a file |

## `cef setup`

```text
proton_cli cef setup
```

Installs the CEF runtime and helper selected by this Proton release in the shared user-level stores and prints the runtime root. It accepts no command-specific options, writes no project runtime-selection file and does not select an arbitrary CEF version. Installation requires network access when artifacts are missing.

## `cef requirements`

```text
proton_cli cef requirements
```

Prints the release's embedded CEF requirement as JSON. It does not install the runtime or inspect an application's running browser. No command-specific options.

## `updater public-key`

```text
proton_cli updater public-key --modulus <hex> [--exponent <hex>]
```

Validates a trusted RSA public key and prints a comment with its bit length followed by `rsa-sha256:<modulus>:<exponent>`, suitable for `App::update_channel`'s `public_keys`.

| Option | Meaning |
| --- | --- |
| `--modulus <hex>` | Required RSA modulus; accepts the `Modulus=` prefix produced by OpenSSL |
| `--exponent <hex>` | Public exponent; default `010001` (65537) |

Surrounding whitespace is trimmed and hexadecimal is normalized to lowercase. The runtime's key parser validates the key, including modulus size and exponent. This command does not generate a key pair, read PEM files, sign artifacts or publish updates.

## Exit status and update checks

| Status | Meaning |
| --- | --- |
| `0` | Command succeeded |
| `1` | Execution failed, or diagnostics reported failure |
| `2` | Argument parsing failed |

Commands other than `version` perform a best-effort CLI update check. `PROTON_NO_UPDATE_CHECK=1` disables it. An unavailable update service does not prevent the command from running.
