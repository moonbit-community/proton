name = "justjavac/proton/examples"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "justjavac/ffi@0.2.1",
  "moonbitlang/async@0.19.0",
  "justjavac/proton_ext@0.1.0",
  "justjavac/proton@0.1.0",
  "justjavac/cdp@0.1.7",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/examples"

license = "MIT"

keywords = [ "webview", "webui", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for webview, a tiny library for creating web-based desktop GUIs."

rule(name: "embed", command: ":embed -i $input -o $output")

rule(
  name: "proton_codegen",
  command: "$mod_dir/../target/proton-tools/proton codegen $input -o $output",
)

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
