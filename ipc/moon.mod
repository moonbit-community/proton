name = "justjavac/lepus_ipc"

version = "0.1.0"

import {
  "moonbitlang/async@0.19.0",
  "moonbitlang/x@0.4.43",
}

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/ipc"

license = "MIT"

keywords = [ "webview", "ipc", "protocol" ]

description = "Transport-neutral IPC protocol types and transports for lepus."

options(
  source: "src",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
