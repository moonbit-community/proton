name = "{{username}}/{{module}}_backend"

version = "0.1.0"

import {
  "{{username}}/{{module}}_shared@0.1.0",
  "moonbitlang/async@0.22.5",
  "moonbit-community/proton@0.6.0",
  "moonbit-community/proton_contract@0.6.0",
}

license = "Apache-2.0"

description = "Proton backend for Proton App."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
