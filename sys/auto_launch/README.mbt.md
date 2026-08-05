# moonbit-community/auto_launch

[![CI](https://github.com/justjavac/moonbit-auto-launch/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/justjavac/moonbit-auto-launch/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-auto-launch)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-auto-launch/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-auto-launch)

Cross-platform auto-launch helpers for MoonBit.

## Example

```mbt check
///|
test "public api can be called" {
  ignore(@auto_launch.current_platform())
  ignore(@auto_launch.is_supported())

  let launcher = @auto_launch.new(
    "MoonBit Demo",
    path=match @auto_launch.current_platform() {
      Windows => "C:\\Program Files\\MoonBit\\moonbit.exe"
      Macos => "/Applications/MoonBit.app/Contents/MacOS/MoonBit"
      Linux => "/usr/bin/moonbit"
      Unsupported => "/unsupported"
    },
    launch_in_background=true,
    extra_arguments=["--serve"],
  )

  match launcher {
    Ok(value) => {
      ignore(value.name())
      ignore(value.path())
      ignore(value.identifier())
    }
    Err(_) => ()
  }
}
```
