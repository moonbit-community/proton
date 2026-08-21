name = "moonbit-community/proton_rabbita"

version = "0.2.1"

import {
  "moonbit-community/proton_client@0.2.1",
  "moonbit-community/proton_contract@0.2.1",
  "moonbit-community/rabbita@0.14.1",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "rabbita", "ipc" ]

description = "Rabbita commands and subscriptions for typed Proton contracts."

options(
  preferred_target: "js",
  supported_targets: "js",
)
