name = "{{username}}/{{module}}_frontend"

version = "0.1.0"

import {
  "{{username}}/{{module}}_shared@0.1.0",
  "moonbit-community/proton_contract@0.9.1",
  "moonbit-community/proton_client@0.9.1",
  "moonbit-community/proton_rabbita@0.9.1",
  "moonbit-community/rabbita@0.16.4",
}

license = "Apache-2.0"

description = "Rabbita frontend for Proton App."

options(
  preferred_target: "js",
  supported_targets: "js",
)
