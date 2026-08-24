name = "moonbit-community/proton_process"

version = "0.2.1"

import {
  "moonbit-community/proton_ffi@0.2.1",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/process"

license = "Apache-2.0"

keywords = [
  "process",
  "spawn",
  "native",
  "windows",
  "linux",
  "macos",
  "child-process",
]

description = "Native child process spawning for MoonBit on Windows, Linux, and macOS."

preferred_target = "native"

source = "."

options(
  supported_targets: "native",
)
