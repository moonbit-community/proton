# Proton Native ABI 优化方案

## 1. 结论

采用 **Proton native 动态库 + MoonBit 直接 FFI**。

默认架构：

```text
MoonBit app
  -> justjavac/proton/native MoonBit binding
  -> proton.dll / libproton.dylib / libproton.so
  -> Proton native browser engine + platform window layer
```

不默认引入动态库加载 shim。这个结论保留，但需要修正一个关键点：**MoonBit-facing ABI 不应优先暴露裸 C 指针**。更适合 MoonBit 的 v1 ABI 是：

- C 内部仍使用真实 CEF 指针和对象。
- C ABI 对 MoonBit 暴露 `int64_t` handle id。
- 创建函数返回状态码，并通过 `int64_t* out_handle` 写出 handle。
- C 侧维护 handle registry，负责校验、销毁、幂等和 use-after-destroy 防护。

这样能同时满足：

- MoonBit 直接用 `extern "C"` 调用。
- 不需要为了 `proton_runtime_t**` 这种 pointer-to-pointer 额外写 adapter。
- 避免 `#external` raw pointer 被复制、重复 destroy、destroy 后继续调用的问题。
- ABI 更容易跨编译器、跨动态库边界验证。

JS bridge 是例外：它涉及底层 browser/renderer IPC、MoonBit callback 生命周期和线程切换，第一版应视为一个单独阶段。Bridge 只有在 callback 模型 spike 通过后才引入 MoonBit adapter stub；否则应改用 event polling。

## 2. 保留和改变

### 保留

- 只做一条 native engine 技术路线；当前实现固定为 CEF。
- 不做 WebView2 / WebKitGTK / WKWebView 多后端抽象。
- C ABI 统一使用 `proton_*`。
- browser engine、平台窗口、多进程细节全部放在 native 动态库。
- MoonBit 侧不直接调用 CEF C API。
- 默认直接链接 `proton` 动态库，不运行时 `dlopen`。

### 改变

- `create` 不再直接返回指针，改为状态码 + out handle。
- public MoonBit `Runtime` / `Window` 不再等于裸 C pointer。
- `load_html` 增加 `base_url`。
- `eval` 明确为 enqueue/fire-and-forget，不承诺同步返回 JS 结果。
- JS bridge 明确经过 CEF renderer -> browser process message。
- Bridge event 必须在 native 层排队；如果采用 callback，只能在约定线程回调 MoonBit。
- `moon.pkg` 不再写一个未定义的 `${build.PROTON_NATIVE_LINK_FLAGS}` 就结束，而是要求平台 link config 生成器。

## 3. 命名

| 对象 | 名称 |
|---|---|
| C ABI 前缀 | `proton_*` |
| Header | `proton_native.h` |
| Windows 动态库 | `proton.dll` |
| Windows import lib | `proton.lib` 或 MinGW import lib |
| macOS 动态库 | `libproton.dylib` |
| Linux 动态库 | `libproton.so` |
| MoonBit 包 | `justjavac/proton/native` 或独立项目 `justjavac/proton_native` |
| MoonBit public types | `Runtime`, `Window`, `RuntimeConfig`, `WindowConfig` |

不建议继续使用 `webview` 作为底层包名或 C ABI 前缀。这里对外是 Proton native runtime；CEF 是内部实现路线，不进入 ABI 命名。

## 4. 总体架构

```text
MoonBit facade / runtime
  |
  | imports
  v
justjavac/proton/native
  |
  | extern "C"
  v
proton dynamic library
  |
  | owns
  v
CEF browser process
  |
  | process message
  v
CEF renderer process / helper process
```

### 4.1 Base binding

基础窗口能力不需要 MoonBit native stub：

- runtime create/destroy/run/quit
- window create/destroy/show/hide/focus
- load URL
- load HTML
- eval script

这些函数只传 `Int64` handle、`Int`、`Bytes`、`Ref[Int64]`，MoonBit FFI 可以直接处理。

### 4.2 Bridge binding

Bridge 如果采用 callback 模型，可以允许一个极薄 adapter：

```text
proton_mbt_adapter.c
```

职责仅限：

- 保存 MoonBit closure 前 `moonbit_incref`。
- unregister / window destroy / runtime destroy 时 `moonbit_decref`。
- C string 复制为 MoonBit-owned `Bytes`。
- 确保 native callback trampoline 调用 MoonBit 的签名正确。

它不是 loader shim，不负责 `LoadLibrary` / `dlopen`。

## 5. C ABI 基础规则

1. `0` 表示成功。
2. 负数表示错误。
3. 正数只用于特殊非错误状态，例如 `execute_process` 表示 subprocess 已处理，或 event polling 当前无事件。
4. `0` handle 永远无效。
5. 所有 handle 是 C registry 里的 `int64_t` id，不是裸 pointer。
6. C registry handle 应包含 generation，避免旧 handle 命中新对象。
7. `destroy` 必须幂等。
8. destroy 后再次调用业务函数返回 `PROTON_ERR_DESTROYED` 或 `PROTON_ERR_INVALID_HANDLE`。
9. 所有 `const char*` 输入都是 UTF-8，C 只在调用期间读取；需要长期保存必须复制。
10. 所有返回给 MoonBit 的字符串都通过 caller-provided buffer 或 callback 参数复制，不跨 allocator 返回 malloc 内存。

## 6. 错误模型

```c
enum {
  PROTON_OK = 0,
  PROTON_PROCESS_HANDLED = 1,
  PROTON_EVENT_NONE = 2,

  PROTON_ERR_INVALID_ARGUMENT = -1,
  PROTON_ERR_INVALID_HANDLE = -2,
  PROTON_ERR_DESTROYED = -3,
  PROTON_ERR_NOT_INITIALIZED = -4,
  PROTON_ERR_ALREADY_INITIALIZED = -5,
  PROTON_ERR_PLATFORM = -6,
  PROTON_ERR_ENGINE = -7,
  PROTON_ERR_UNSUPPORTED = -8,
  PROTON_ERR_WRONG_THREAD = -9,
  PROTON_ERR_QUEUE_FAILED = -10,
  PROTON_ERR_BUFFER_TOO_SMALL = -11
};
```

错误信息规则：

- `last_error` 必须是 thread-local。
- 只保证在同一线程、下一次 `proton_*` 调用前有效。
- `proton_last_error_message(NULL, 0)` 返回需要的 UTF-8 byte 长度，不含 trailing nul。
- 传入 buffer 时复制 nul-terminated 字符串，返回完整所需长度。

```c
PROTON_API int32_t proton_last_error_message(
  char* buffer,
  int32_t buffer_len
);
```

MoonBit safe wrapper 不直接暴露 status code。它把负数转换成 MoonBit error，并把 `last_error` 附上。

## 7. C Header v1 草案

```c
#ifndef PROTON_NATIVE_H
#define PROTON_NATIVE_H

#include <stdint.h>

#ifdef _WIN32
  #ifdef PROTON_BUILD
    #define PROTON_API __declspec(dllexport)
  #else
    #define PROTON_API __declspec(dllimport)
  #endif
#else
  #define PROTON_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define PROTON_ABI_VERSION 1
#define PROTON_INVALID_HANDLE 0

typedef int64_t proton_runtime_id_t;
typedef int64_t proton_window_id_t;

enum {
  PROTON_OK = 0,
  PROTON_PROCESS_HANDLED = 1,
  PROTON_EVENT_NONE = 2,

  PROTON_ERR_INVALID_ARGUMENT = -1,
  PROTON_ERR_INVALID_HANDLE = -2,
  PROTON_ERR_DESTROYED = -3,
  PROTON_ERR_NOT_INITIALIZED = -4,
  PROTON_ERR_ALREADY_INITIALIZED = -5,
  PROTON_ERR_PLATFORM = -6,
  PROTON_ERR_ENGINE = -7,
  PROTON_ERR_UNSUPPORTED = -8,
  PROTON_ERR_WRONG_THREAD = -9,
  PROTON_ERR_QUEUE_FAILED = -10,
  PROTON_ERR_BUFFER_TOO_SMALL = -11
};

PROTON_API int32_t proton_abi_version(void);
PROTON_API int32_t proton_runtime_info_json(
  char* buffer,
  int32_t buffer_len,
  int32_t* out_required_len
);

PROTON_API int32_t proton_execute_process(
  const char* config_json,
  int32_t* out_exit_code
);

PROTON_API int32_t proton_runtime_probe_json(
  const char* config_json
);

PROTON_API int32_t proton_runtime_create_json(
  const char* config_json,
  proton_runtime_id_t* out_runtime
);

PROTON_API int32_t proton_runtime_destroy(
  proton_runtime_id_t runtime
);

PROTON_API int32_t proton_runtime_run(
  proton_runtime_id_t runtime
);

PROTON_API int32_t proton_runtime_quit(
  proton_runtime_id_t runtime
);

PROTON_API int32_t proton_window_create_json(
  proton_runtime_id_t runtime,
  const char* config_json,
  proton_window_id_t* out_window
);

PROTON_API int32_t proton_window_destroy(
  proton_window_id_t window
);

PROTON_API int32_t proton_window_show(
  proton_window_id_t window
);

PROTON_API int32_t proton_window_hide(
  proton_window_id_t window
);

PROTON_API int32_t proton_window_close(
  proton_window_id_t window
);

PROTON_API int32_t proton_window_focus(
  proton_window_id_t window
);

PROTON_API int32_t proton_window_set_title(
  proton_window_id_t window,
  const char* title
);

PROTON_API int32_t proton_window_set_size(
  proton_window_id_t window,
  int32_t width,
  int32_t height
);

PROTON_API int32_t proton_window_load_url(
  proton_window_id_t window,
  const char* url
);

PROTON_API int32_t proton_window_load_html(
  proton_window_id_t window,
  const char* html,
  const char* base_url
);

PROTON_API int32_t proton_window_eval(
  proton_window_id_t window,
  const char* script
);

PROTON_API int32_t proton_last_error_message(
  char* buffer,
  int32_t buffer_len
);

#ifdef __cplusplus
}
#endif

#endif
```

## 8. 配置 JSON

使用 JSON 是为了避免 ABI 很快膨胀。Native runtime 配置项多，且各平台不同；用固定参数列表会很快需要 `create2/create3`。

### 8.1 RuntimeConfig

```json
{
  "abi_version": 1,
  "runtime_root": "path/to/runtime",
  "helper_path": "path/to/cef_process.exe",
  "use_bundled": false,
  "resources_dir": "path/to/resources",
  "locales_dir": "path/to/locales",
  "cache_dir": "path/to/cache",
  "remote_debugging_port": 0
}
```

规则：

- `abi_version` 必填。
- 所有路径进入 C 后必须复制。
- Windows 内部转换为 wide path。
- 缺省值由 native 层决定，但必须文档化。
- v1 不暴露任意 browser command-line switches；只允许 native 层维护固定安全默认值。
- v1 不暴露 `external_message_pump`；如果未来支持外部事件循环，再新增 `proton_runtime_do_message_loop_work` 和对应 config。
- `helper_path` 是对外命名；native 内部可以把它映射到具体 engine 的 subprocess/helper executable。
- `use_bundled=true` 表示使用随包发布的安装布局：从已加载的 `proton.dll`/`libproton` 位置推导 `runtime_root`，并使用同目录下的 `bin/cef_process.exe`，应用代码不需要硬编码 CEF SDK 路径。

### 8.2 WindowConfig

```json
{
  "abi_version": 1,
  "title": "Proton",
  "width": 1024,
  "height": 768,
  "initial_url": "about:blank"
}
```

规则：

- `width` / `height` 在 MoonBit 层先校验。
- `initial_url` 可选；没有则加载 `about:blank`。
- `load_html` 必须额外传 `base_url`，不要把 origin 语义藏起来。

## 9. 底层进程和生命周期

### 9.0 runtime layout probe

`proton_runtime_probe_json` 用于在初始化前验证 runtime 分发布局。它只检查
`runtime_root`、`helper_path`、resources、locales 和核心 runtime 文件，不加载
browser engine。

`runtime_root` 允许两类布局：

```text
sdk-root/
  Release/libcef.dll
  Resources/icudtl.dat
  Resources/locales/

installed-app-root/
  bin/libcef.dll
  Resources/icudtl.dat
  Resources/locales/
```

Linux 对应为 `runtime_root/libcef.so` 或 `runtime_root/lib/libcef.so`；
macOS 对应 framework root 或 `Frameworks/` 下的 framework。

如果 `Runtime::new` 或 `execute_process` 收到包含 `runtime_root` / `helper_path`
的 config，它必须按真实 engine config 处理：先 probe；probe 成功后如果当前
DLL 未以 engine 支持构建，则返回 `PROTON_ERR_UNSUPPORTED`。它不能悄悄退回到
fake runtime handle。

### 9.1 execute_process

`proton_execute_process` 必须在应用入口尽早调用。

推荐 MoonBit 应用启动顺序：

```text
main
  -> proton_execute_process(config)
     -> returns PROTON_PROCESS_HANDLED:
          exit(out_exit_code)
     -> returns PROTON_OK:
          continue browser process startup
  -> Runtime::new(config)
  -> Window::new(...)
  -> Runtime::run()
```

`execute_process` 不能藏在 `Runtime::new` 里，因为 subprocess 分支必须尽早退出，不能初始化完整应用 runtime。

### 9.2 runtime

`Runtime::new` 对应 browser process 初始化。

v1 选择 native-owned blocking loop：

```text
Runtime::run() blocks
Runtime::quit() requests loop exit
```

如果未来要让 MoonBit 自己 pump message loop，再单独增加：

```c
proton_runtime_do_message_loop_work(runtime)
```

不要在 v1 同时支持 blocking loop 和 external pump，两个模型混在一起会导致平台差异扩大。

### 9.3 window

`Window::destroy` 的语义：

- 可以重复调用。
- 第一次调用关闭 native window 并释放 handle registry entry。
- 后续调用返回 OK 或 `ERR_DESTROYED`，MoonBit wrapper 统一视为 no-op。
- runtime destroy 会关闭仍存在的子窗口。

## 10. 线程模型

CEF 有自己的 UI / IO / renderer 线程模型。MoonBit binding 必须有明确约束：

1. MoonBit 只从创建 runtime 的线程调用 public API。
2. native 层接到 API 调用后，如果当前不在 CEF UI 线程，应投递任务到 CEF UI 线程。
3. `load_url`、`load_html`、`eval` 返回的成功只表示任务已成功入队，不表示页面已完成加载或 JS 已执行成功。
4. native 层不能从任意 CEF 线程直接调用 MoonBit callback。
5. Bridge event 必须先排队，再在 `Runtime::run` 所在线程触发 MoonBit callback。

如果第 5 条无法实现，应先禁用 bridge，不要暴露一个会随机跨线程调用 MoonBit 的 API。

## 11. JS Bridge 设计

JS bridge 不能只设计为 C callback。CEF 的 JS 执行在 renderer process，MoonBit app 在 browser process。

如果采用 callback 模型，正确路径是：

```text
JS window.__MoonBit__.core.invokeOp(...)
  -> renderer process V8 handler
  -> CefProcessMessage
  -> browser process
  -> native bridge queue
  -> MoonBit callback on runtime run thread
  -> proton_bridge_respond(...)
  -> browser process
  -> renderer process
  -> resolve/reject JS Promise
```

这个模型不是 v1 默认承诺。它必须先证明 MoonBit 可以在 blocking `Runtime::run` 的 native 调用中被稳定反调；否则应改成 `proton_runtime_poll_event(...)` 这类 event polling 模型。

### 11.1 Bridge callback 候选 ABI

```c
typedef void (*proton_bridge_callback_t)(
  proton_runtime_id_t runtime,
  proton_window_id_t window,
  int64_t request_id,
  const char* name,
  const char* payload_json,
  void* userdata
);

typedef void (*proton_userdata_release_t)(void* userdata);

PROTON_API int32_t proton_runtime_set_bridge_handler(
  proton_runtime_id_t runtime,
  proton_bridge_callback_t callback,
  void* userdata,
  proton_userdata_release_t release_userdata
);

PROTON_API int32_t proton_bridge_respond(
  proton_runtime_id_t runtime,
  int64_t request_id,
  int32_t status,
  const char* result_json
);
```

### 11.2 Bridge 生命周期

- `name` 和 `payload_json` 只在 callback 调用期间有效。
- callback adapter 必须复制它们。
- `request_id` 由 native 层生成并保证 runtime 内唯一。
- window destroy 后，该 window 的 pending request 应 reject。
- runtime destroy 前必须 release `userdata`。
- callback 只能在 `Runtime::run` 线程触发。

## 12. MoonBit FFI 设计

### 12.1 Raw extern

`ffi.mbt` 中 extern 保持 private。

```moonbit
///|
#borrow(config_json, out_exit_code)
extern "C" fn execute_process(
  config_json : Bytes,
  out_exit_code : Ref[Int],
) -> Int = "proton_execute_process"

///|
#borrow(config_json, out_runtime)
extern "C" fn runtime_create_json(
  config_json : Bytes,
  out_runtime : Ref[Int64],
) -> Int = "proton_runtime_create_json"

///|
extern "C" fn runtime_destroy(runtime : Int64) -> Int =
  "proton_runtime_destroy"

///|
extern "C" fn runtime_run(runtime : Int64) -> Int =
  "proton_runtime_run"

///|
extern "C" fn runtime_quit(runtime : Int64) -> Int =
  "proton_runtime_quit"

///|
#borrow(config_json, out_window)
extern "C" fn window_create_json(
  runtime : Int64,
  config_json : Bytes,
  out_window : Ref[Int64],
) -> Int = "proton_window_create_json"

///|
#borrow(url)
extern "C" fn window_load_url(window : Int64, url : Bytes) -> Int =
  "proton_window_load_url"

///|
#borrow(html, base_url)
extern "C" fn window_load_html(
  window : Int64,
  html : Bytes,
  base_url : Bytes,
) -> Int = "proton_window_load_html"
```

### 12.2 Safe public API

Public API 不暴露 raw `Int64`。

```moonbit
///|
pub struct Runtime {
  handle : Int64
}

///|
pub struct Window {
  handle : Int64
}

///|
pub fn execute_process(config : RuntimeConfig) -> ProcessResult raise

///|
pub fn Runtime::new(config : RuntimeConfig) -> Runtime raise

///|
pub fn Runtime::destroy(self : Runtime) -> Unit raise

///|
pub fn Runtime::run(self : Runtime) -> Unit raise

///|
pub fn Runtime::quit(self : Runtime) -> Unit raise

///|
pub fn Window::new(runtime : Runtime, config : WindowConfig) -> Window raise

///|
pub fn Window::load_url(self : Window, url : String) -> Unit raise

///|
pub fn Window::load_html(
  self : Window,
  html : String,
  base_url : String
) -> Unit raise
```

MoonBit wrapper 必须做：

- `width > 0`
- `height > 0`
- handle 不为 0
- string -> UTF-8 bytes
- status -> error
- destroy 幂等语义包装
- `RuntimeConfig` / `WindowConfig` 的普通 constructor 只接受 typed options；raw JSON 只能通过 `unsafe_from_json(...)` 这类显式 escape hatch。

## 13. moon.pkg 和链接配置

不要在 `moon.pkg` 中硬编码平台链接参数。沿用当前项目已有思路：由脚本生成 build variables / link configs。

### 13.1 moon.pkg

```moonbit
import {
  "moonbitlang/core/json",
  "moonbitlang/core/encoding/utf8",
}

options(
  targets: {
    "ffi.mbt": [ "native" ],
    "native.mbt": [ "native" ],
    "error.mbt": [ "native" ],
  },
  link: {
    "native": {
      "cc-link-flags": "${build.PROTON_NATIVE_LINK_FLAGS}"
    }
  }
)
```

如果 bridge 采用 callback adapter：

```moonbit
options(
  "native-stub": [ "proton_mbt_adapter.c" ],
  link: {
    "native": {
      "cc-link-flags": "${build.PROTON_NATIVE_LINK_FLAGS}",
      "stub-cc-flags": "${build.PROTON_NATIVE_STUB_CC_FLAGS}"
    }
  }
)
```

### 13.2 native_link_config.mjs

生成内容至少包括：

```json
{
  "vars": {
    "PROTON_NATIVE_LINK_FLAGS": "...",
    "PROTON_NATIVE_STUB_CC_FLAGS": "...",
    "PROTON_NATIVE_RUNTIME_DIR": "...",
    "PROTON_RUNTIME_ROOT": "...",
    "PROTON_HELPER_PATH": "..."
  },
  "link_configs": []
}
```

默认安装前缀是仓库内 `native/dist`。开发者或 CI 可以通过
`PROTON_NATIVE_DIST` 覆盖它，使 MoonBit direct FFI 指向另一个已安装的
`proton` 动态库目录；脚本据此生成 `PROTON_NATIVE_LINK_FLAGS` 和
`PROTON_NATIVE_RUNTIME_DIR`。

各平台分别生成：

- Windows MSVC flags
- Windows MinGW/TCC flags
- macOS `-L`, `-lproton`, `-rpath`
- Linux `-L`, `-lproton`, `$ORIGIN` rpath

### 13.3 native CMake options

Standalone native DLL 默认可以先编译 ABI/binding spike，不链接 browser
engine。真实 engine 构建必须显式开启：

```text
cmake -S native -B native/build \
  -DPROTON_WITH_ENGINE=ON \
  -DPROTON_ENGINE_ROOT=/path/to/runtime-sdk
```

Windows 下 `PROTON_ENGINE_ROOT` 至少需要：

```text
Release/libcef.lib
Release/libcef.dll
Resources/icudtl.dat
Resources/locales/
```

`cmake --install` 产物应形成 app-style layout：Windows 把 `Release/*.dll`
安装到 `bin/`，并把 `Resources/` 安装到 install root 的 `Resources/`。

默认 `PROTON_WITH_ENGINE=OFF` 时，`proton_runtime_probe_json` 仍可验证 layout；
但 `Runtime::new(config)` / `execute_process(config)` 收到 engine config 后应返回
`PROTON_ERR_UNSUPPORTED`，不能创建 fake runtime。

Engine-specific code lives behind `native/src/proton_engine.h`:

- `PROTON_WITH_ENGINE=OFF`: compile `proton_engine_none.c` for ABI/binding tests.
- `PROTON_WITH_ENGINE=ON` on Windows: compile `proton_engine_cef_win.c`.
- `PROTON_WITH_ENGINE=ON` on Linux/macOS: fail at configure time until platform engine sources are wired.

The Windows CEF engine implementation should progress in layers:

1. `cef_execute_process` and `cef_initialize`.
2. Runtime handle integration with initialized engine state.
3. Win32 window + browser creation.
4. Navigation/load/eval operations.
5. Events and bridge IPC.

## 14. 动态库加载 shim 决策

默认不做 loader shim。

保留两个清晰层次：

| 层 | 是否默认 | 用途 |
|---|---|---|
| MoonBit adapter stub | bridge callback 模型才需要 | MoonBit closure 生命周期和 callback trampoline |
| dynamic loader shim | 不默认 | `LoadLibrary` / `dlopen`，绕过 import lib 或运行时选库 |

如果目标是继续使用 MoonBit 内置 TCC，需要单独 spike：

1. 预编译 `proton.dll`。
2. 验证 TCC 能否链接 import library。
3. 如果不能，评估 loader shim。

不要为了 TCC 提前污染主 ABI。先让默认路径稳定可分发。

## 15. Windows 分发

```text
app/
  myapp.exe
  proton.dll
  cef_process.exe
  libcef.dll
  chrome_elf.dll
  icudtl.dat
  snapshot_blob.bin
  v8_context_snapshot.bin
  resources/
  locales/
```

注意：

- `cef_process.exe` 必须和 CEF 配置一致。
- CEF 资源文件必须由 packaging 脚本复制，不能靠用户手动放。
- Windows path 在 native 层转 wide char。
- sandbox 策略先由 native 层固定；生产模式必须在新增 public config 前重新评估。

## 16. macOS 分发

macOS 不是单 dylib 问题，必须按 app bundle 设计。

```text
MyApp.app/
  Contents/
    Info.plist
    MacOS/
      MyApp
    Frameworks/
      libproton.dylib
      Chromium Embedded Framework.framework
    Helpers/
      MyApp Helper.app
      MyApp Helper (Renderer).app
      MyApp Helper (GPU).app
    Resources/
```

必须处理：

- `@rpath`
- `install_name`
- helper app bundle id
- signing
- notarization
- hardened runtime
- CEF framework resources

macOS 不建议作为第一平台实现。

## 17. Linux 分发

```text
app/
  bin/myapp
  lib/libproton.so
  lib/libcef.so
  lib/*.so
  resources/
  locales/
  chrome-sandbox
```

链接示例：

```text
-L/path/to/app/lib -lproton -Wl,-rpath,'$ORIGIN/../lib'
```

必须处理：

- GTK / X11 / Wayland / Ozone
- NSS
- GBM
- ALSA / PulseAudio
- sandbox
- `chrome-sandbox` 权限

dev 模式可先由 native 层禁用 sandbox，生产包必须重新评估 sandbox。

## 18. 实施阶段

### Phase 0: ABI spike

先验证 MoonBit 能否稳定使用：

- `Ref[Int64]` out-param。
- `Bytes` UTF-8 入参。
- `FixedArray[Byte]` 错误 buffer。
- link config 脚本注入 flags。

验收：

```bash
moon check --target native
moon test --target native
```

### Phase 1: Native DLL 最小闭环

实现：

- `proton_abi_version`
- `proton_last_error_message`
- handle registry
- create/destroy fake runtime

先不引入 CEF，先把 ABI 和 MoonBit binding 跑通。

### Phase 2: Native browser process

实现：

- `proton_execute_process`
- `proton_runtime_create_json`
- `proton_runtime_run`
- `proton_runtime_quit`
- native runtime resource path 解析
- subprocess path 解析

### Phase 3: Window

实现：

- `proton_window_create_json`
- `show/hide/focus/close`
- `load_url`
- `load_html(html, base_url)`
- `eval` enqueue

### Phase 4: MoonBit safe API

实现：

- `RuntimeConfig`
- `WindowConfig`
- JSON encoding
- status -> error
- destroy 幂等封装
- README.mbt.md example

### Phase 5: JS bridge

实现：

- renderer V8 binding
- renderer -> browser process message
- browser event queue
- MoonBit event polling 或 callback adapter
- `bridge_respond`
- pending request cleanup

### Phase 6: Packaging

按平台分别实现：

1. Windows
2. Linux
3. macOS

## 19. 测试清单

MoonBit:

```bash
moon fmt
moon check --target native
moon test --target native
moon info --target native
```

Native:

```bash
cmake --build build --config Release
ctest --test-dir build
```

Windows 一键验证当前 DLL + MoonBit direct FFI：

```powershell
cmake -S native -B native\build-engine ^
  -DCMAKE_INSTALL_PREFIX=native\dist ^
  -DPROTON_WITH_ENGINE=ON ^
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
ctest --test-dir native\build-engine -C Debug --output-on-failure
node native\scripts\verify_link_config.mjs native\dist
```

这个目标会安装 `proton.dll` / `proton.lib`，运行 native smoke test，
并带着 `native/dist/bin` 进入 `PATH` 运行：

```bash
moon -C proton test native --target native --diagnostic-limit 80
moon -C proton check --target native --diagnostic-limit 80
moon -C proton info --target native
```

必须覆盖：

- ABI version mismatch。
- runtime info JSON contains ABI, runtime availability, build mode, platform,
  and public feature metadata。
- invalid JSON config。
- missing runtime root。
- missing subprocess。
- handle = 0。
- invalid handle generation。
- destroy twice。
- runtime destroy before window destroy。
- load URL before browser ready。
- load HTML with base URL。
- eval after window destroy。
- bridge request during window close。
- pending request cleanup。
- app exit has no subprocess leak。

内存：

- handle create/destroy loop。
- window create/destroy loop。
- bridge callback register/unregister loop。
- ASan or platform equivalent。

## 20. Review 后必须修正的问题

这一版方向是对的，但还有几处不能留成“实现时再说”。这些问题不解决，ABI 看起来很薄，落地时会被生命周期、线程和分发细节反噬。

### 20.1 JSON config 必须有稳定 schema

JSON 适合避免 ABI 参数膨胀，但不能变成无类型垃圾桶。需要在 v1 明确：

- `abi_version` 和 `schema_version` 的关系：建议只保留 `abi_version`，它同时约束 C ABI 和 config schema。
- 未知字段策略：v1 建议默认报 `PROTON_ERR_INVALID_ARGUMENT`，不要静默忽略，否则拼错字段很难发现。
- 必填字段和默认值：默认值必须写进文档和测试，不要只存在 C++ 代码里。
- 路径字段必须规定相对路径基准：建议相对 app executable directory，而不是当前工作目录。
- v1 不暴露任意 command-line switches；未来如需开放，必须使用白名单并能在生产模式禁用危险项。

### 20.2 handle registry 不能只是 `int64_t -> pointer`

`Int64` handle 是正确方向，但 registry 设计需要更硬：

- handle 至少包含 index + generation；建议再包含 type tag，避免 runtime handle 被传给 window API。
- registry 必须加锁或限制所有访问都在 owner thread；两者只能选一个主模型。
- destroy 不能立即复用 generation；至少 generation 递增并保留 tombstone 状态，便于返回 `PROTON_ERR_DESTROYED`。
- runtime destroy 时要先标记 runtime closing，再关闭 windows，再释放底层 engine 对象。
- 每个 API 入口都要校验 handle type、generation、destroyed、owner runtime。

### 20.3 `last_error` 只适合同步错误

thread-local `last_error` 可以保留，但不能承载 async 结果：

- enqueue 成功但后续页面加载失败，不能写进同一个 `last_error`。
- bridge request 失败要走 `proton_bridge_respond` 或 event queue，不要依赖 `last_error`。
- C API 返回 `PROTON_ERR_QUEUE_FAILED` 时，`last_error` 才描述入队失败本身。
- 如果未来增加事件 API，事件 payload 必须包含 status、message、window、request_id。

### 20.4 `Runtime::destroy(self : Runtime)` 的 MoonBit 封装不够安全

如果 `Runtime` / `Window` 是只含 `Int64` 的值类型，`destroy(self)` 不能把调用者手里的 handle 置 0。native 幂等能防重复释放，但防不了后续误用。

建议 MoonBit safe API 采用其中一种：

- `Runtime` / `Window` 内部持有可变状态对象，destroy 后把 handle 置为 `PROTON_INVALID_HANDLE`。
- 或者明确它们是 affine-style 资源，文档要求 destroy 后不可再用，并让所有后续调用映射成 MoonBit error。

不要依赖 GC finalizer 自动关闭窗口。UI 资源和多进程退出需要确定性关闭；finalizer 最多作为泄漏兜底。

### 20.5 blocking `Runtime::run` 与 MoonBit callback 需要先 spike

当前方案说 bridge event 在 `Runtime::run` 所在线程回调 MoonBit。这个模型可行的前提是：native 在一次阻塞 FFI 调用期间反向调用 MoonBit callback 是稳定的，且 MoonBit runtime 允许这种重入。

必须先做最小 spike：

- MoonBit 注册 callback。
- C `runtime_run` 阻塞并周期性触发 callback。
- callback 中能分配 `Bytes`、解析 JSON、调用 `bridge_respond`。
- quit 后 callback 生命周期正确释放，没有 use-after-free。

如果 spike 不通过，v1 应改为 external pump 模型：

```c
PROTON_API int32_t proton_runtime_poll_event_json(
  proton_runtime_id_t runtime,
  char* buffer,
  int32_t buffer_len,
  int32_t* out_required_len
);

PROTON_API int32_t proton_runtime_do_message_loop_work(
  proton_runtime_id_t runtime
);
```

`proton_runtime_poll_event_json` 返回 `PROTON_OK` 表示已复制一个 nul-terminated event JSON，返回 `PROTON_EVENT_NONE` 表示当前无事件，返回 `PROTON_ERR_BUFFER_TOO_SMALL` 表示 buffer 不够并通过 `out_required_len` 写出 JSON byte 长度；该长度不含 trailing nul，调用方需要准备 `out_required_len + 1` 的 buffer。

这会让 MoonBit 主循环主动 poll 事件，牺牲一点易用性，但线程边界更可控。

### 20.6 window ready 和导航事件不能缺席

`load_url` / `load_html` 返回 enqueue 成功，不代表 browser 已创建、页面已加载或 JS 可执行。因此 v1 至少需要一种事件机制，否则示例会天然 race：

- `window_created`
- `dom_ready` 或 `load_end`
- `load_error`
- `window_closed`

如果暂时不做通用事件 ABI，至少要规定 native 层缓存 early `load_*` 操作，等 browser ready 后按顺序执行。

### 20.7 JS bridge 是安全边界，不只是 IPC

`window.__MoonBit__.core.invokeOp(...)` 等价于把 native capability 暴露给页面。v1 必须默认保守：

- 默认只注入到 app-controlled 页面，远程 URL 默认禁用 bridge。
- 需要 origin allowlist。
- op name 走 MoonBit/core 注册表，不允许任意 native function dispatch。
- payload size 需要上限，避免页面把 native queue 打爆。
- pending request 要有 timeout 或 window close reject 策略。

### 20.8 直接 FFI 不等于没有加载问题

不做 loader shim 是正确默认值，但直接链接动态库仍然要求：

- build 阶段找到 import lib / `.so` / `.dylib`。
- run 阶段 OS loader 能找到 `proton` 和底层 runtime 依赖。
- 缺库时错误可能发生在 `main` 之前，`proton_runtime_info_json()` 没机会执行。

因此必须配套 packaging / launcher：

- Windows 设置 exe 同目录分发，或开发模式临时设置 `PATH`。
- macOS 设置 `@rpath`、bundle Frameworks 和 Helpers。
- Linux 设置 `$ORIGIN` rpath 或 launcher 设置 `LD_LIBRARY_PATH`。

loader shim 仍然不是默认 ABI 的一部分；它只在 TCC/import-lib 兼容性或错误诊断明显受阻时作为单独包评估。

### 20.9 CMake install/package 是交付物，不是附属脚本

只说“编译成 DLL”不够。native 项目必须提供：

- `cmake --install` 输出可运行 runtime layout。
- 复制 browser engine 资源、locales、helper executable、sandbox 文件。
- 生成 MoonBit `native_link_config` 需要的 library path、runtime path、rpath flags。
- Windows 同时产出 MSVC import lib；如果支持 MinGW/TCC，需要单独产出兼容 import lib。
- 版本文件：`proton_abi_version()`、动态库版本、资源包版本必须能比对。

### 20.10 第一版范围要再收窄

建议 v1 不把全部能力一次纳入验收。更稳的顺序是：

1. Base ABI spike：fake runtime + handle registry + MoonBit direct FFI。
2. Real runtime：能初始化、run、quit，无 window。
3. Window：create/show/load_url/load_html，先不做 bridge。
4. Events：window ready/load_end/load_error/closed。
5. Bridge：确认 callback 重入或改成 poll event 后再做。
6. Packaging：每个平台都以 `cmake --install` 产物为准。

## 21. 当前最大难点

1. CEF 多进程和 helper packaging。
2. JS bridge 的 renderer/browser IPC。
3. MoonBit callback 生命周期和线程约束。
4. Windows import library 与 TCC 的兼容性。
5. macOS bundle/signing/notarization。
6. Linux sandbox 和系统依赖。

## 22. 最终推荐路线

1. `proton` 动态库独立构建。
2. MoonBit-facing ABI 使用 `Int64` handle id。
3. `create` 使用状态码 + `Ref[Int64]` out-param。
4. Runtime/window config 使用 JSON，避免 ABI 参数膨胀。
5. Base window API 直接 FFI，不写 loader shim。
6. Bridge 阶段优先验证 event polling；只有 callback 模型 spike 通过时才允许 MoonBit adapter stub，且只处理 callback 生命周期。
7. 默认不追求 TCC 直接链接 CEF import library；TCC 作为独立 spike。
8. Windows 先落地，Linux 第二，macOS 第三。
