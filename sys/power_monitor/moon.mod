name = "moonbit-community/proton_power_monitor"

version = "0.1.18"

import {
  "moonbit-community/proton_ffi@0.1.18",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/power_monitor"

license = "Apache-2.0"

keywords = [
  "power-monitor",
  "native",
  "windows",
  "linux",
  "macos",
  "power-management",
]

description = "Native power and idle state queries for MoonBit on Windows, Linux, and macOS."

preferred_target = "native"

source = "."

options(
  supported_targets: "native",
)
