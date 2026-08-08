name = "moonbit-community/proton_config"

version = "0.1.14"

import {
  "moonbitlang/lexer@0.3.13",
  "moonbitlang/moon_config@0.3.5",
  "moonbitlang/x@0.4.49",
}

repository = "https://github.com/moonbit-community/proton"

license = "Apache-2.0"

description = "Typed config parser for Proton moon.proton and moon.ext files."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
