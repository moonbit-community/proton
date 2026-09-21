name = "moonbit-community/proton_ext"

version = "0.3.2"

import {
  "moonbit-community/proton_ffi@0.3.2",
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.1",
  "moonbit-community/proton_clipboard@0.3.2",
  "moonbit-community/proton_safe_storage@0.3.2",
  "moonbit-community/proton_tray@0.3.2",
  "moonbit-community/proton_global_hotkey@0.3.2",
  "moonbit-community/proton@0.3.2",
  "moonbit-community/proton_contract@0.3.2",
  "moonbit-community/proton_microphone@0.3.2",
  "moonbit-community/proton_auto_launch@0.3.2",
  "moonbit-community/proton_keepawake@0.3.2",
  "moonbit-community/proton_power_monitor@0.3.2",
  "moonbit-community/proton_screen_monitor@0.3.2",
  "moonbit-community/proton_shell@0.3.2",
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
