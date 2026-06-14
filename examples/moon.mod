name = "justjavac/lepus/examples"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_bootstrap@0.1.0",
  "justjavac/lepus_app@0.1.0",
  "justjavac/lepus_core@0.1.0",
  "justjavac/lepus_manifest@0.1.0",
  "justjavac/ffi@0.2.1",
  "moonbitlang/async@0.19.0",
  "extensions@0.1.0",
  "justjavac/lepus_runtime@0.1.0",
  "justjavac/lepus@0.1.10",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/lepus/tree/main/examples"

license = "MIT"

keywords = [ "webview", "webui", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for webview, a tiny library for creating web-based desktop GUIs."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
