name = "justjavac/lepus_manifest"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
}

options(
  readme: "README.md",
  repository: "https://github.com/justjavac/lepus/tree/main/manifest",
  license: "MIT",
  keywords: [ "webview", "manifest", "config", "desktop-app" ],
  description: "Declarative manifest types for lepus applications.",
  source: ".",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
