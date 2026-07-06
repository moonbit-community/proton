name = "justjavac/proton_config"

version = "0.1.4"

import {
  "moonbitlang/lexer@0.3.4",
  "moonbitlang/parser@0.3.2",
  "moonbitlang/x@0.4.43",
}

repository = "https://github.com/moonbit-community/proton"

license = "MIT"

description = "Typed config parser for Proton moon.proton and moon.ext files."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
