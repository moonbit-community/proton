name = "moonbit-community/proton_client"

version = "0.2.0"

import {
  "moonbitlang/async@0.21.0",
  "moonbit-community/proton_contract@0.2.0",
}

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "client", "ipc" ]

description = "Typed asynchronous frontend client for Proton applications."

options(
  preferred_target: "js",
  supported_targets: "js",
)
