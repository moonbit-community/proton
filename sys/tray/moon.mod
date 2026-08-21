name = "moonbit-community/proton_tray"

version = "0.2.1"

import {
  "moonbit-community/proton_ffi@0.2.1",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/tray"

license = "Apache-2.0"

keywords = [ "tray", "desktop", "native", "windows", "macos", "linux" ]

description = "Cross-platform native tray helpers for MoonBit."

preferred_target = "native"

source = "."

options(
  supported_targets: "+native",
)
