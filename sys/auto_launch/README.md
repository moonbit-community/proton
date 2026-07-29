# justjavac/auto_launch

[![CI](https://github.com/justjavac/moonbit-auto-launch/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/justjavac/moonbit-auto-launch/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-auto-launch)

Cross-platform auto-launch helpers for MoonBit.

This project is inspired by and references [Teamwork/node-auto-launch](https://github.com/Teamwork/node-auto-launch). The API shape, platform choices, and overall package direction in this repository were designed with that project as the main reference and source of inspiration.

## Features

- Windows: stores startup commands in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- macOS: writes a LaunchAgent plist to `~/Library/LaunchAgents`
- Linux: writes a desktop entry to `~/.config/autostart`
- Optional hidden/background startup argument support
- Small synchronous MoonBit API with `Result`-based error handling

## Install

```bash
moon add justjavac/auto_launch
```

This package currently supports the `native` target.

## Example

```moonbit
fn main {
  let launcher = match @auto_launch.new(
    "MoonBit Demo",
    path=match @auto_launch.current_platform() {
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

- `@auto_launch.current_platform() -> Platform`
- `@auto_launch.is_supported() -> Bool`
- `@auto_launch.new(...) -> Result[AutoLaunch, AutoLaunchError]`
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

# Coverage for the main package only; excludes src/examples/*
moon test --target native --enable-coverage
moon coverage analyze -p justjavac/auto_launch -- -f summary
moon info --target native
```

Optional side-effect integration test:

```bash
$env:MOONBIT_AUTO_LAUNCH_RUN_INTEGRATION_TESTS = "1"
moon test --target native --filter "integration*"
```

## Examples

```bash
moon run src/examples/check_status --target native
moon run src/examples/enable --target native
moon run src/examples/disable --target native
```

## License

MIT. See [LICENSE](LICENSE).
