name = "justjavac/lepus_core"

version = "0.1.0"

import {
  "justjavac/ffi@0.2.1",
  "moonbitlang/async@0.19.0",
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_ipc@0.1.0",
  "justjavac/lepus@0.1.10",
}

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/core"

license = "MIT"

keywords = [ "webview", "runtime", "extension", "bridge" ]

description = "Core bridge and extension host for lepus."

options(
  source: "src",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
