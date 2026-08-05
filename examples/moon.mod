name = "justjavac/proton/examples"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.48",
  "moonbitlang/async@0.20.3",
  "justjavac/proton_ext@0.1.7",
  "justjavac/proton_contract@0.1.1",
  "justjavac/proton@0.1.14",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/examples"

license = "Apache-2.0"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "MoonBit examples for the Proton native desktop runtime facade."

rule(name: "embed", command: ":embed -i $input -o $output")

rule(
  name: "proton_codegen",
  command: "moon -C $mod_dir/../cli run --target-dir ../target/proton-codegen-moon . -- -C $mod_dir codegen $input -o $output",
)

rule(
  name: "proton_extension_identity_codegen",
  command: "moon -C $mod_dir/../cli run --target-dir ../target/proton-codegen-moon . -- -C $mod_dir codegen --extension-identity $input -o $output",
)

source = ""

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
