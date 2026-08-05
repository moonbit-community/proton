name = "moonbit-community/proton_ext"

version = "0.1.7"

import {
  "moonbit-community/ffi@0.2.4",
  "moonbitlang/x@0.4.48",
  "moonbitlang/async@0.20.3",
  "moonbit-community/clipboard@0.1.5",
  "moonbit-community/tray@0.1.7",
  "moonbit-community/global_hotkey@0.1.4",
  "moonbit-community/proton@0.1.14",
  "moonbit-community/proton_contract@0.1.1",
  "moonbit-community/microphone@0.1.3",
  "moonbit-community/auto_launch@0.1.3",
  "moonbit-community/keepawake@0.1.0",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/extensions"

license = "Apache-2.0"

keywords = [ "proton", "extension", "filesystem" ]

description = "Extensions for proton examples and applications."

source = "."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
