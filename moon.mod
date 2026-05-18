name = "justjavac/lepus"

version = "0.1.10"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/x@0.4.43",
}

options(
  readme: "README.md",
  repository: "https://github.com/justjavac/lepus",
  license: "MIT",
  keywords: [ "webview", "webui", "gui", "web", "desktop-app" ],
  description: "MoonBit bindings for webview, a tiny library for creating web-based desktop GUIs.",
  source: "src",
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
