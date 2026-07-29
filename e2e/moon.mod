name = "justjavac/proton/e2e"

version = "0.1.0"

import {
  "moonbitlang/async@0.19.0",
  "moonbitlang/x@0.4.43",
  "justjavac/cdp@0.1.7",
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
