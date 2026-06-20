name = "justjavac/proton_ext"

version = "0.1.0"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.0",
  "justjavac/clipboard@0.1.5",
  "justjavac/notification@0.1.0",
  "justjavac/tray@0.1.0",
  "justjavac/global_hotkey@0.1.0",
  "justjavac/proton@0.1.10",
  "justjavac/microphone@0.1.0",
  "justjavac/auto_launch@0.1.3",
  "justjavac/keepawake@0.1.0",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/extensions"

license = "MIT"

keywords = [ "webview", "extension", "filesystem" ]

description = "Extensions for proton examples and applications."

options(
  source: ".",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
