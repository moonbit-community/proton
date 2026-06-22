name = "justjavac/proton"

version = "0.1.2"

import {
  "justjavac/ffi@0.2.1",
  "justjavac/proton_config@0.1.2",
  "moonbitlang/async@0.19.0",
  "moonbitlang/x@0.4.43",
  "moonbitlang/lexer@0.3.4",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton"

license = "MIT"

keywords = [ "webview", "webui", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for webview, a tiny library for creating web-based desktop GUIs."

options(
  source: "src",
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
