# moonbit-community/proton_auto_launch

Cross-platform auto-launch helpers for MoonBit.

This project is inspired by and references [Teamwork/node-auto-launch](https://github.com/Teamwork/node-auto-launch). The API shape, platform choices, and overall package direction in this repository were designed with that project as the main reference and source of inspiration.

## Features

- Windows: stores startup commands in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- macOS: writes a LaunchAgent plist to `~/Library/LaunchAgents`
- Linux: writes a desktop entry to `~/.config/autostart`
- Optional hidden/background startup argument support
- Small synchronous MoonBit API with `Result`-based error handling

Pass executable paths and arguments as literal values, without adding quotes or
escaping them yourself. On Linux, Proton encodes them for the desktop entry;
arguments such as `%f` remain literal rather than acting as launcher field codes.
Linux launches through `/usr/bin/env` so executable paths containing `%` also
work with GLib and systemd desktop-entry consumers. Executable paths must be
absolute and must not contain `=`; Linux returns `UnsupportedExecutablePath` for
the latter because `env` interprets it as an environment assignment. Arguments
may contain `=`. Existing entries must be regenerated with `enable()` after
upgrading. Older systemd generators have separate backslash-escape limitations,
including `$` and backticks; arbitrary arguments are not portable
across all desktop-entry consumers.

## Install

```bash
moon add moonbit-community/proton_auto_launch
```

This package currently supports the `native` target.

## Example

```moonbit
fn main {
  let launcher = match @proton_auto_launch.new(
    "MoonBit Demo",
    path=match @proton_auto_launch.current_platform() {
      Windows => "C:\\Program Files\\MoonBit\\moonbit.exe"
      Macos => "/Applications/MoonBit.app/Contents/MacOS/MoonBit"
      Linux => "/usr/bin/moonbit"
      Unsupported => "/unsupported"
    },
    launch_in_background=true,
    extra_arguments=["--serve"],
  ) {
    Ok(value) => value
    Err(error) => fail("failed to create launcher: \{error}")
  }

  match launcher.enable() {
    Ok(_) => println("auto-launch enabled")
    Err(error) => println("enable failed: \{error}")
  }
}
```

## API

- `@proton_auto_launch.current_platform() -> Platform`
- `@proton_auto_launch.is_supported() -> Bool`
- `@proton_auto_launch.new(...) -> Result[AutoLaunch, AutoLaunchError]`
- `AutoLaunch::name() -> String`
- `AutoLaunch::path() -> String`
- `AutoLaunch::identifier() -> String`
- `AutoLaunch::enable() -> Result[Unit, AutoLaunchError]`
- `AutoLaunch::disable() -> Result[Unit, AutoLaunchError]`
- `AutoLaunch::is_enabled() -> Result[Bool, AutoLaunchError]`

## Testing

```bash
moon fmt
moon check --target native
moon test --target native

moon test --target native --enable-coverage
moon coverage analyze -p moonbit-community/proton_auto_launch -- -f summary
moon info --target native
```

Optional side-effect integration test:

```bash
$env:MOONBIT_AUTO_LAUNCH_RUN_INTEGRATION_TESTS = "1"
moon test --target native --filter "integration*"
```

## License

Apache-2.0. See [LICENSE](LICENSE).
