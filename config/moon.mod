name = "moonbit-community/proton_config"

version = "0.1.16"

import {
  "moonbitlang/moon_config@0.3.13",
  "moonbitlang/x@0.4.50",
}

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

description = "Typed project configuration models and JSON decoding for Proton."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
