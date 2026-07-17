name = "justjavac/proton/e2e"

version = "0.1.0"

import {
  "moonbitlang/async@0.19.0",
  "justjavac/cdp@0.1.7",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/e2e"

license = "Apache-2.0"

keywords = [ "proton", "cef", "cdp", "e2e" ]

description = "CEF end-to-end bridge smoke probes for Proton examples."

source = ""

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
