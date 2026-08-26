name = "moonbit-community/proton_global_hotkey"

version = "0.2.2"

import {
  "moonbit-community/proton_ffi@0.2.2",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/global_hotkey"

license = "Apache-2.0"

keywords = [
  "desktop",
  "shortcut",
  "hotkey",
  "native",
  "windows",
  "macos",
  "linux",
]

description = "Cross-platform native global hotkey helpers for MoonBit."

preferred_target = "native"

source = "."

options(
  supported_targets: "+native",
)
