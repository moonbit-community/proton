name = "moonbit-community/proton_cefsetup"

version = "0.1.19"

import {
  "moonbitlang/async@0.20.5",
  "moonbitlang/x@0.4.50",
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
