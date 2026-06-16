name = "justjavac/lepus_bootstrap"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.45",
  "justjavac/lepus_manifest@0.1.0",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/lepus/tree/main/bootstrap"

license = "MIT"

keywords = [ "webview", "bootstrap", "manifest", "desktop-app" ]

description = "Bootstrap helpers for loading declarative lepus manifests."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
