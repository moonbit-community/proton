name = "justjavac/proton_rabbita"

version = "0.1.0"

import {
  "justjavac/proton_client@0.1.0",
  "justjavac/proton_contract@0.1.0",
  "moonbit-community/rabbita@0.12.4",
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
