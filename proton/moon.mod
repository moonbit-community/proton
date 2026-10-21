name = "moonbit-community/proton"

version = "0.5.1"

import {
  "moonbit-community/proton_ffi@0.5.1",
  "moonbit-community/proton_config@0.5.1",
  "moonbit-community/proton_contract@0.5.1",
  "moonbit-community/proton_updater@0.5.1",
  "moonbit-community/proton_rsa@0.5.1",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
  "moonbitlang/lexer@0.4.2",
  "tonyfettes/xlog@0.4.2",
  "marianoguerra/uri@0.1.2",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "MoonBit bindings for the Proton native desktop runtime."

preferred_target = "native"

supported_targets = "+native"

options(
  "--moonbit-unstable-prebuild": "build.mjs",
  warn_list: "",
)
