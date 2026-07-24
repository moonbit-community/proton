name = "justjavac/proton"

version = "0.1.12"

import {
  "justjavac/ffi@0.2.1",
  "justjavac/proton_config@0.1.7",
  "moonbitlang/async@0.19.4",
  "moonbitlang/x@0.4.43",
  "moonbitlang/lexer@0.3.4",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for the Proton native desktop runtime."

options(
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
