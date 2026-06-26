name = "justjavac/proton_ext"

version = "0.1.3"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.0",
  "justjavac/clipboard@0.1.5",
  "justjavac/notification@0.1.0",
  "justjavac/tray@0.1.0",
  "justjavac/global_hotkey@0.1.0",
  "justjavac/proton@0.1.2",
  "justjavac/microphone@0.1.0",
  "justjavac/auto_launch@0.1.3",
  "justjavac/keepawake@0.1.0",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/extensions"

license = "MIT"

keywords = [ "proton", "extension", "filesystem" ]

description = "Extensions for proton examples and applications."

rule(
  name: "proton_codegen",
  command: "moon -C $mod_dir/../cli run --target-dir ../target/proton-codegen-moon . -- codegen $mod_dir/$input -o $mod_dir/$output",
)

options(
  source: ".",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
