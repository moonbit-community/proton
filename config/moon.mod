name = "moonbit-community/proton_config"

version = "0.8.0"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.5",
  "tonyfettes/url@0.3.5",
}

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

description = "Typed application configuration shared by Proton and its CLI."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
