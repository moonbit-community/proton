name = "{{username}}/{{module}}"

version = "0.1.0"

import {
  "moonbitlang/async@0.22.5",
  "moonbit-community/proton@0.6.0",
}

license = "Apache-2.0"

description = "A minimal Proton desktop application."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
