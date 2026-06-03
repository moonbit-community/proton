name = "justjavac/lepus_manifest"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/lepus/tree/main/manifest"

license = "MIT"

keywords = [ "webview", "manifest", "config", "desktop-app" ]

description = "Declarative manifest types for lepus applications."

options(
  source: ".",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
