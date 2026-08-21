name = "moonbit-community/proton_bundle"

version = "0.2.0"

import {
  "moonbit-community/proton_package@0.2.0",
  "moonbit-community/proton_cefsetup@0.2.0",
  "moonbitlang/async@0.21.0",
  "moonbitlang/x@0.5.1",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/bundle"

license = "Apache-2.0"

keywords = [ "proton", "bundle", "packaging", "cef" ]

description = "Proton-specific application bundle assembly over proton_package."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
