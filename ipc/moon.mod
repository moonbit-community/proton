name = "justjavac/lepus_ipc"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/ipc"

license = "MIT"

keywords = [ "webview", "ipc", "protocol" ]

description = "Transport-neutral IPC protocol types for lepus."

options(
  source: "src",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
