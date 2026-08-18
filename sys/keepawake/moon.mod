name = "moonbit-community/proton_keepawake"

version = "0.1.18"

import {
  "moonbit-community/proton_ffi@0.1.18",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/keepawake"

license = "Apache-2.0"

keywords = [
  "keepawake",
  "native",
  "windows",
  "linux",
  "macos",
  "power-management",
]

description = "Native keep-awake guards for MoonBit on Windows, Linux, and macOS."

preferred_target = "native"

source = "."

options(
  supported_targets: "native",
)
