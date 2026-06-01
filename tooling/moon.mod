name = "justjavac/lepus_tooling"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_bootstrap@0.1.0",
  "justjavac/lepus_manifest@0.1.0",
  "justjavac/lepus_catalog@0.1.0",
}

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/tooling"

license = "MIT"

keywords = [ "webview", "tooling", "extension", "metadata" ]

description = "AI- and developer-facing catalog query and registry code generation helpers for lepus."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
