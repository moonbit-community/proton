name = "moonbit-community/proton_config"

version = "0.1.19"

import {
  "moonbitlang/x@0.5.1",
}

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

description = "Typed CLI project configuration and JSON decoding for Proton."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
