name = "{{username}}/{{module}}_backend"

version = "0.1.0"

import {
  "{{username}}/{{module}}_shared@0.1.0",
  // Proton 0.8.0 uses the standalone API. This version shares core/async's runtime.
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton@0.8.0",
  "moonbit-community/proton_contract@0.8.0",
}

license = "Apache-2.0"

description = "Proton backend for Proton App."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
