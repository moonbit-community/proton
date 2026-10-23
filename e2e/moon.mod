name = "moonbit-community/proton/e2e"

version = "0.6.0"

import {
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
  "moonbit-community/proton_cdp@0.6.0",
  "moonbit-community/proton@0.6.0",
  "moonbit-community/proton_cefsetup@0.6.0",
  "moonbit-community/proton_updater@0.6.0",
  "moonbit-community/proton/examples@0.6.0",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/e2e"

license = "Apache-2.0"

keywords = [ "proton", "cef", "cdp", "e2e" ]

description = "CDP-based native bridge end-to-end tests for Proton examples."

source = ""

preferred_target = "native"

supported_targets = "+native"

options(
  warn_list: "",
)
