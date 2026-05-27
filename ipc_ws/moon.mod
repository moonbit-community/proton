name = "justjavac/lepus_ipc_ws"

version = "0.1.0"

import {
  "moonbitlang/async@0.19.0",
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_ipc@0.1.0",
}

options(
  readme: "README.md",
  repository: "https://github.com/justjavac/lepus/tree/main/ipc_ws",
  license: "MIT",
  keywords: [ "webview", "ipc", "websocket" ],
  description: "HTTP/WebSocket IPC transport for lepus.",
  source: "src",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
