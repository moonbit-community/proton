name = "moonbit-community/proton_cefsetup"

version = "0.2.0"

import {
  "moonbitlang/async@0.21.0",
  "moonbitlang/x@0.5.1",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cefsetup"

license = "Apache-2.0"

keywords = [ "proton", "cef", "setup" ]

description = "Install the CEF runtime required by Proton."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
