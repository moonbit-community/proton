name = "moonbit-community/keepawake"

version = "0.1.14"

import {
  "moonbit-community/ffi@0.1.14",
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
