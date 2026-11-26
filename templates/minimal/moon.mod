name = "{{username}}/{{module}}"

version = "0.1.0"

import {
  // Keep standalone async dependencies on the core/async compatibility bridge.
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton@0.9.1",
}

license = "Apache-2.0"

description = "A minimal Proton desktop application."

options(
  preferred_target: "native",
  supported_targets: "+native",
)
