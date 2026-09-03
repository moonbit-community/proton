name = "moonbit-community/proton_package"

version = "0.2.7"

import {
  "moonbitlang/async@0.21.2",
  "moonbitlang/x@0.5.1",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/package"

license = "Apache-2.0"

keywords = [ "desktop", "package", "app", "dmg", "nsis", "appimage" ]

description = "Host-native desktop application packaging library and CLI."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
