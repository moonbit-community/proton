name = "moonbit-community/proton_package"

version = "0.1.18"

import {
  "moonbitlang/async@0.20.5",
  "moonbitlang/x@0.4.50",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/package"

license = "Apache-2.0"

keywords = [ "desktop", "package", "app", "dmg", "nsis", "appimage" ]

description = "Host-native desktop application packaging library and CLI."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "native",
)
