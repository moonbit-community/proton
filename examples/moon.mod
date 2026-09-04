name = "moonbit-community/proton/examples"

version = "0.2.8"

import {
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.2",
  "moonbit-community/proton_ext@0.2.8",
  "moonbit-community/proton_contract@0.2.8",
  "moonbit-community/proton@0.2.8",
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

preferred_target = "native"

supported_targets = "+native"

options(
  warn_list: "",
)
