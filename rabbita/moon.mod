name = "moonbit-community/proton_rabbita"

version = "0.8.0"

import {
  // Rabbita still uses the standalone package. Share core/async's runtime.
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton_client@0.8.0",
  "moonbit-community/proton_contract@0.8.0",
  "moonbit-community/rabbita@0.16.4",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "rabbita", "ipc" ]

description = "Rabbita commands and subscriptions for typed Proton contracts."

preferred_target = "js"

supported_targets = "js"
