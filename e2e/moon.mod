name = "justjavac/proton/e2e"

version = "0.1.0"

import {
  "moonbitlang/async@0.20.3",
  "moonbitlang/x@0.4.48",
  "justjavac/cdp@0.1.9",
  "justjavac/proton@0.1.14",
  "justjavac/proton_updater@0.1.0",
  "justjavac/proton/examples@0.1.0",
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
