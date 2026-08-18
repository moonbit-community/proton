name = "moonbit-community/proton_shell"

version = "0.1.17"

import {
  "moonbit-community/proton_ffi@0.1.17",
}

repository = "https://github.com/moonbit-community/proton/tree/main/sys/shell"

license = "Apache-2.0"

keywords = [ "shell", "desktop", "native", "windows" ]

description = "Native shell helpers for MoonBit."

preferred_target = "native"

source = "."

options(
  supported_targets: "+native",
)
