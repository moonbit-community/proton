name = "moonbit-community/proton_screen_monitor"

version = "0.1.18"

import {
  "moonbit-community/proton_ffi@0.1.18",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/screen_monitor"

license = "Apache-2.0"

keywords = [
  "screen",
  "display",
  "monitor",
  "native",
  "windows",
  "linux",
  "macos",
]

description = "Native screen and display queries plus hot-plug events for MoonBit on Windows, Linux, and macOS."

preferred_target = "native"

source = "."

options(
  supported_targets: "native",
)
