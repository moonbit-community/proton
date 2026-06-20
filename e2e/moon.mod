name = "justjavac/proton/e2e"

version = "0.1.0"

import {
  "moonbitlang/async@0.19.0",
  "justjavac/cdp@0.1.7",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/e2e"

license = "MIT"

keywords = [ "webview", "cef", "cdp", "e2e" ]

description = "CEF end-to-end smoke probes for Proton examples."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
