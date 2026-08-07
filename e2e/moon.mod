name = "moonbit-community/proton/e2e"

version = "0.1.14"

import {
  "moonbitlang/async@0.20.4",
  "moonbitlang/x@0.4.48",
  "moonbit-community/proton_cdp@0.1.14",
  "moonbit-community/proton@0.1.14",
  "moonbit-community/proton_updater@0.1.14",
  "moonbit-community/proton/examples@0.1.14",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/e2e"

license = "Apache-2.0"

keywords = [ "proton", "cef", "cdp", "e2e" ]

description = "CDP-based native bridge end-to-end tests for Proton examples."

source = ""

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
