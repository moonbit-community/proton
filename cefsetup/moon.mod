name = "moonbit-community/proton_cefsetup"

version = "0.3.2"

import {
  "moonbitlang/async@0.22.1",
  "moonbitlang/x@0.5.5",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cefsetup"

license = "Apache-2.0"

keywords = [ "proton", "cef", "setup" ]

description = "Install the CEF runtime and subprocess helper required by Proton."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
