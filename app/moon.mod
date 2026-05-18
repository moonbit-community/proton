name = "justjavac/lepus_app"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_bootstrap@0.1.0",
  "justjavac/lepus_core@0.1.0",
  "justjavac/lepus_manifest@0.1.0",
  "justjavac/lepus@0.1.10",
  "justjavac/lepus_runtime@0.1.0",
}

options(
  readme: "README.md",
  repository: "https://github.com/justjavac/lepus/tree/main/app",
  license: "MIT",
  keywords: [ "webview", "app", "manifest", "desktop-app" ],
  description: "High-level manifest and registry based app composition for lepus.",
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
