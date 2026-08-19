name = "moonbit-community/proton/examples"

version = "0.1.19"

import {
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.20.5",
  "moonbit-community/proton_ext@0.1.19",
  "moonbit-community/proton_contract@0.1.19",
  "moonbit-community/proton@0.1.19",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/examples"

license = "Apache-2.0"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "MoonBit examples for the Proton native desktop runtime facade."

rule(name: "embed", command: ":embed -i $input -o $output")

rule(
  name: "proton_codegen",
  command: "moon -C \"$mod_dir/../codegen\" run --target-dir \"$mod_dir/../codegen/_build\" --target wasm . -- -C \"$mod_dir\" \"$input\" -o \"$output\"",
)

rule(
  name: "proton_extension_identity_codegen",
  command: "moon -C \"$mod_dir/../codegen\" run --target-dir \"$mod_dir/../codegen/_build\" --target wasm . -- -C \"$mod_dir\" --extension-identity \"$input\" -o \"$output\"",
)

source = ""

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
