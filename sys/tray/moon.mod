name = "justjavac/tray"

version = "0.1.7"

import {
  "justjavac/ffi@0.2.3",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/tray"

license = "MIT"

keywords = [ "tray", "desktop", "native", "windows", "macos", "linux" ]

description = "Cross-platform native tray helpers for MoonBit."

preferred_target = "native"

source = "."

options(
  supported_targets: "+native",
)
