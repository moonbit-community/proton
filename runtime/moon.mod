name = "justjavac/lepus_runtime"

version = "0.1.0"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/x@0.4.45",
  "justjavac/lepus_core@0.1.0",
  "justjavac/lepus_ipc@0.1.0",
  "justjavac/lepus@0.1.10",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/lepus/tree/main/runtime"

license = "MIT"

keywords = [ "webview", "runtime", "extension", "desktop-app" ]

description = "Ops runtime and app framework for lepus."

options(
  source: "src",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
