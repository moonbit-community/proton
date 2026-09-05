name = "moonbit-community/proton_ext"

version = "0.2.8"

import {
  "moonbit-community/proton_ffi@0.2.8",
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.2",
  "moonbit-community/proton_clipboard@0.2.8",
  "moonbit-community/proton_safe_storage@0.2.8",
  "moonbit-community/proton_tray@0.2.8",
  "moonbit-community/proton_global_hotkey@0.2.8",
  "moonbit-community/proton@0.2.8",
  "moonbit-community/proton_contract@0.2.8",
  "moonbit-community/proton_microphone@0.2.8",
  "moonbit-community/proton_auto_launch@0.2.8",
  "moonbit-community/proton_keepawake@0.2.8",
  "moonbit-community/proton_power_monitor@0.2.8",
  "moonbit-community/proton_screen_monitor@0.2.8",
  "moonbit-community/proton_shell@0.2.8",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/extensions"

license = "Apache-2.0"

keywords = [ "proton", "extension", "filesystem" ]

description = "Extensions for proton examples and applications."

source = "."

preferred_target = "native"

supported_targets = "+native"

options(
  warn_list: "",
)
