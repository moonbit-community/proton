name = "extensions"

version = "0.1.0"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.0",
  "justjavac/clipboard@0.1.5",
  "justjavac/notification@0.1.0",
  "justjavac/tray@0.1.0",
  "justjavac/global_hotkey@0.1.0",
  "justjavac/lepus_catalog@0.1.0",
  "justjavac/lepus_core@0.1.0",
  "justjavac/lepus@0.1.10",
  "justjavac/microphone@0.1.0",
  "justjavac/auto_launch@0.1.3",
  "justjavac/keepawake@0.1.0",
}

options(
  readme: "README.md",
  repository: "https://github.com/justjavac/lepus/tree/main/extensions",
  license: "MIT",
  keywords: [ "webview", "extension", "filesystem" ],
  description: "Extensions for lepus examples and applications.",
  source: ".",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
