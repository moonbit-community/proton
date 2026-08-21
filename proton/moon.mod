name = "moonbit-community/proton"

version = "0.1.19"

import {
  "moonbit-community/proton_ffi@0.1.19",
  "moonbit-community/proton_config@0.1.19",
  "moonbit-community/proton_contract@0.1.19",
  "moonbit-community/proton_updater@0.1.19",
  "moonbit-community/proton_rsa@0.1.19",
  "moonbitlang/async@0.20.5",
  "moonbitlang/x@0.4.50",
  "moonbitlang/lexer@0.3.13",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for the Proton native desktop runtime."

options(
  "--moonbit-unstable-prebuild": "build.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
