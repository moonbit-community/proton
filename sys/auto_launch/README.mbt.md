# moonbit-community/proton_auto_launch

[![CI](https://github.com/moonbit-community/proton/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/moonbit-community/proton/actions/workflows/ci.yml)

Cross-platform auto-launch helpers for MoonBit.

## Example

```mbt check
///|
test "public api can be called" {
  ignore(@proton_auto_launch.current_platform())
  ignore(@proton_auto_launch.is_supported())

  let launcher = @proton_auto_launch.new(
    "MoonBit Demo",
    path=match @proton_auto_launch.current_platform() {
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
