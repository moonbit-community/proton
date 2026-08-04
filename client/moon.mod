name = "justjavac/proton_client"

version = "0.1.1"

import {
  "moonbitlang/async@0.19.4",
  "justjavac/proton_contract@0.1.1",
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
