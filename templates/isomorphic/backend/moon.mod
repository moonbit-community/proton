name = "{{username}}/{{module}}_backend"

version = "0.1.0"

import {
  "{{username}}/{{module}}_shared@0.1.0",
  // Keep standalone async dependencies on the core/async compatibility bridge.
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton@0.9.1",
  "moonbit-community/proton_contract@0.9.1",
}

license = "Apache-2.0"

description = "Proton backend for Proton App."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
