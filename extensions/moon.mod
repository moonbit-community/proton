name = "moonbit-community/proton_ext"

version = "0.1.17"

import {
  "moonbit-community/proton_ffi@0.1.17",
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.20.5",
  "moonbit-community/proton_clipboard@0.1.17",
  "moonbit-community/proton_tray@0.1.17",
  "moonbit-community/proton_global_hotkey@0.1.17",
  "moonbit-community/proton@0.1.17",
  "moonbit-community/proton_contract@0.1.17",
  "moonbit-community/proton_microphone@0.1.17",
  "moonbit-community/proton_auto_launch@0.1.17",
  "moonbit-community/proton_keepawake@0.1.17",
  "moonbit-community/proton_power_monitor@0.1.17",
  "moonbit-community/proton_process@0.1.17",
  "moonbit-community/proton_shell@0.1.17",
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
