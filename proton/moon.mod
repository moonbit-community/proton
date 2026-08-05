name = "justjavac/proton"

version = "0.1.14"

import {
  "justjavac/ffi@0.2.3",
  "justjavac/proton_config@0.1.8",
  "justjavac/proton_contract@0.1.1",
  "justjavac/proton_updater@0.1.0",
  "justjavac/proton_rsa@0.1.0",
  "moonbitlang/async@0.20.3",
  "moonbitlang/x@0.4.48",
  "moonbitlang/lexer@0.3.12",
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
