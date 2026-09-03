name = "moonbit-community/proton_cli"

version = "0.2.7"

import {
  "moonbit-community/proton_config@0.2.7",
  "moonbit-community/proton_package@0.2.7",
  "moonbit-community/proton_cefsetup@0.2.7",
  "moonbit-community/proton_rsa@0.2.7",
  "moonbit-community/proton_updater@0.2.7",
  "moonbitlang/x@0.5.1",
  "moonbitlang/moon_config@0.3.14",
  "moonbitlang/async@0.21.2",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "Apache-2.0"

keywords = [ "proton", "cli", "desktop" ]

description = "Developer CLI for Proton desktop applications."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
