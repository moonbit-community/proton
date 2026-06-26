# Proton Bridge Plan

## 1. 结论

Proton 当前只保留一条 runtime 路线：

```text
MoonBit app
  -> justjavac/proton
  -> proton.dll / libproton.dylib / libproton.so
  -> native browser runtime
  -> cef_process.exe helper
```

CEF 是 native 内部实现细节。MoonBit 只链接 Proton native 动态库或 import library，不直接链接 CEF；公开 C ABI 继续使用 `proton_*`；MoonBit 包名、facade API、C ABI 前缀都不暴露 CEF。

Bridge 的最小闭环已经落地：

```text
JS page
  -> window.__MoonBit__.core.invokeOp(op, payload)
  -> renderer V8 handler
  -> CEF process message
  -> browser/main process in proton.dll
  -> native bridge request queue
  -> MoonBit polls request
  -> MoonBit dispatches registered command op
  -> MoonBit sends response JSON
  -> browser/main process
  -> renderer resolves/rejects JS Promise
```

新增的 command-extension proxy 不改 C ABI。facade 只在 inline HTML entry 中注入一层 JS bootstrap，根据 enabled `AppCommandExtensionSpec` 生成：

```js
window.__MoonBit__.add.slowAdd(payload)
window.__MoonBit__.math.double(payload)
```

这些 proxy 只是调用现有 `window.__MoonBit__.core.invokeOp("ext:<namespace>/<api>", payload)`，没有引入新的 native bridge 协议。

## 2. 当前状态

已经实现：

- CMake 构建并安装 `proton.dll` / import library / `cef_process.exe`。
- MoonBit 通过 `native_link_config.mjs` 链接 Proton native library。
- `native/include/proton_native.h` 暴露 bridge v1 所需 C ABI。
- `proton/native` 提供 private extern 和 safe wrapper。
- root `proton` facade 在有 command extension 时使用 pump loop，不走 blocking `Runtime::run()`。
- inline HTML 通过 `Window::load_html(html, "proton://app/")` 进入 app-controlled `proton://app/` origin。
- native bridge 只注入 `proton://` 页面；`about:blank`、`file://`、`http://` 默认没有 bridge。
- native 按 `bridge_json.ops` 做 allowlist，unknown op 直接 reject，不进入 MoonBit queue。
- browser/main process 维护 `request_id -> renderer target` pending map，response 回到正确 renderer。
- reload/context release、window close、runtime destroy 都有 pending cleanup 路径。
- inline HTML command extension proxy 已覆盖 `38_async_extension_add` 和 `39_sync_async_extensions`。
- inline HTML command extension event broadcast 已覆盖 `40_event_broadcast`。
- attribute-codegen command metadata 已覆盖 `42_attribute_codegen_commands`，仍走同一套 inline HTML proxy 和 native DLL bridge。
- `scripts/e2e_bridge_smoke.mjs` 要求 `e2e/` 已经列在 `moon.work` 中；脚本不再运行时修改 workspace。

暂不实现：

- streaming op。
- binary payload。
- remote page bridge。
- 多 runtime 之间的 bridge 协调。

## 3. 不变量

1. C ABI 使用 `proton_*`。
2. MoonBit 只链接 Proton native library，不链接 CEF。
3. `native/CMakeLists.txt` 是唯一 native build source of truth。
4. 不引入 loader shim，除非独立 import-library/TCC spike 证明必须要。
5. 不引入 MoonBit callback adapter stub。
6. 不恢复旧 `proton/cef_process` MoonBit helper。
7. `cef_process.exe` 是 native packaged helper，随 `proton.dll` 发布。
8. C ABI 只传 `Int64` handle、UTF-8 JSON、caller-owned buffer、status code。
9. bridge config、request、response JSON 必须有显式 `abi_version`。
10. 默认只给 app-controlled `proton://` 页面注入 bridge。
11. 远程 URL 默认没有 `window.__MoonBit__`。
12. JS 只能调用 MoonBit registry 注册过的 op，不能调用任意 native function。

## 4. 当前 JS Surface

低层 bridge：

```js
await window.__MoonBit__.core.invokeOp("ext:app/ping", { name: "MoonBit" });
```

inline HTML command-extension proxy：

```js
await window.__MoonBit__.add.slowAdd({ left: 2, right: 3 });
await window.__MoonBit__.math.double({ value: 21 });
```

proxy 生成规则：

- 来源是 enabled command extension 的 `js_namespace()` 和 `apis()`。
- 每个 API proxy 调用 `core.invokeOp("ext:<namespace>/<api>", payload)`。
- 每个 namespace 还提供 `invoke(apiName, payload)` 作为通用入口。
- 每个 namespace 提供 `on(eventName, listener)`，内部订阅 `events.on("<namespace>.<eventName>", listener)`。
- `events['@@emitExtensionEvent'](namespace, eventName, payload)` 是 native/facade 投递事件的内部入口。
- `core`、`events`、空名称、JS 保留属性、`then` 等名称不生成 proxy。
- 当前只注入 inline HTML；URL/file/asset entry 暂不做 HTML 注入。

仍不承诺：

- `window.__MoonBit__.fs.readFile(...)` 这类非 command-extension metadata 驱动的 proxy。
- remote page bridge。

## 5. C ABI v1

`native/include/proton_native.h` 面向 MoonBit 暴露：

```c
PROTON_API int32_t proton_runtime_do_message_loop_work(
    proton_runtime_id_t runtime);

PROTON_API int32_t proton_window_install_bridge_json(
    proton_window_id_t window,
    const char *bridge_json);

PROTON_API int32_t proton_runtime_poll_bridge_request_json(
    proton_runtime_id_t runtime,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len);

PROTON_API int32_t proton_runtime_respond_bridge_request_json(
    proton_runtime_id_t runtime,
    const char *response_json);
```

关键约束：

- `proton_runtime_do_message_loop_work` 非阻塞，只能在 runtime owner thread 调用。
- 安装 bridge 后 facade 必须使用 MoonBit pump loop。
- `proton_window_install_bridge_json` 复制传入 JSON，不保存调用方指针。
- native 根据 `ops` 做第一层 allowlist。
- `poll_bridge_request_json` 使用 caller-owned buffer 和 `out_required_len` 协议。
- `respond_bridge_request_json` 用 `request_id` 找到 pending JS Promise；stale response 返回明确错误，facade 可忽略 window close/reload 引起的 stale completion。

## 6. Pump 策略

固定 `@async.sleep(1)` 不作为正式设计。facade 使用 adaptive cooperative pump：

- 每轮先执行 `runtime.do_message_loop_work()`。
- 处理 window event、bridge request、completed bridge task。
- 本轮有 work 时下一轮立即继续，并 `@async.sleep(0)` 让出调度。
- 本轮 idle 时逐步 backoff，当前上限 16ms。
- `cef_do_message_loop_work()` 返回 `void`，不能靠返回值判断是否有 CEF work。

后续如果 MoonBit async runtime 能安全等待 native wake event，可以再升级为 event-driven wait；当前不新增 ABI。

## 7. `cef_process.exe`

`cef_process.exe` 是 CEF subprocess helper，不是 MoonBit package，也不是 bridge 层。

主进程初始化 CEF 时设置 `browser_subprocess_path` 指向它。CEF 启动 renderer、GPU、utility 等子进程时，这些进程进入 `cef_process.exe`，再由 `proton_execute_process(...)` 调用 `cef_execute_process(...)`。

不建议省掉它：

- 不设置 `browser_subprocess_path` 时，CEF 通常会尝试把当前 executable 当子进程入口。
- MoonBit app exe 不适合作为 renderer/GPU/utility helper。
- 让每个 MoonBit app 自己处理 `cef_execute_process` 会把 CEF 进程模型泄漏给用户。
- CEF single-process 模式不适合作为生产路线。

真实 runtime 发布包必须包含 native dynamic library 和 `cef_process.exe`。

## 8. Security

Bridge 是 native capability 边界，必须持续验证：

- 只给 `proton://` 页面注入 bridge。
- `@proton.url(...)` 加载远程 URL 时默认没有 bridge。
- 未来如允许远程 URL，必须显式 origin allowlist。
- JS op 必须来自 MoonBit registry。
- native 层必须按 `bridge_json.ops` 做 allowlist。
- unknown op 不进入 MoonBit queue。
- payload byte length 有上限。
- queue length 有上限。
- request 有 timeout 设计空间。
- window close、runtime destroy、reload/context release 都要清理 pending state。

## 9. E2E 覆盖

已通过：

- `41_app_commands`
  - `core.invokeOp` 可见。
  - `ext:app/ping` resolve。
  - `ext:app/slowAdd` resolve，且不阻塞 pump loop。
  - unknown op reject，且 native log 证明未入队。
  - oversized payload reject，且未进入 browser queue。
  - queue full reject。
  - handler failure reject。
  - reload 后 bridge 重新注入。
  - `about:blank`、`file://`、`http://` 不暴露 bridge。
  - window close/runtime destroy cleanup。
- `45_bridge_multi_window`
  - 两个窗口同时发 request 时 response 不串窗。
  - native log 证明 request id 和 browser id 隔离。
- `38_async_extension_add`
  - `window.__MoonBit__.add.slowAdd(...)` proxy 注入。
  - proxy 调用进入 native bridge queue。
  - async command response 正确返回。
- `39_sync_async_extensions`
  - `window.__MoonBit__.math.double(...)` proxy 注入。
  - `window.__MoonBit__.add.slowAdd(...)` proxy 注入。
  - sync/async command response 正确返回。
- `40_event_broadcast`
  - `window.__MoonBit__.ticker.start(...)` proxy 注入。
  - `window.__MoonBit__.ticker.on(...)` 订阅事件。
  - `context.emit("tick", ...)` 和 `context.emit("done", ...)` 能广播到 JS listener。
  - command response 和事件流都正确返回。
  - reload 后 event proxy 重新注入，后续 command response 和事件流仍正确返回。
  - window close 时 pending event command 不导致进程失败，native log 证明 pending state 被清理。
- `42_attribute_codegen_commands`
  - generated `window.__MoonBit__.add.slowAdd(...)` proxy 注入。
  - generated `emit_add_finished(...)` helper 能广播 `add.addFinished` 到 JS listener。
  - command response 和 generated event 都正确返回。

运行 e2e 前应确认 `e2e/` 已经列在 `moon.work` 中。

验证命令：

```powershell
node scripts\e2e_bridge_smoke.mjs 38_async_extension_add 39_sync_async_extensions
node scripts\e2e_bridge_smoke.mjs 40_event_broadcast
node scripts\e2e_bridge_smoke.mjs 42_attribute_codegen_commands
node scripts\e2e_bridge_smoke.mjs 41_app_commands 45_bridge_multi_window
```

## 10. 后续可选项

1. 如需排查 CEF 时序，再临时启用 `PROTON_NATIVE_LOG_VERBOSE`，不要把高频日志恢复到普通 `PROTON_NATIVE_LOG`。
2. 如需支持 streaming op、binary payload、remote page bridge 或多 runtime bridge 协调，必须先补独立设计，不应混入 bridge v1。

## 11. FFI 修改要求

实现或修改 FFI 前必须重新检查 MoonBit C binding 规则：

- `Bytes` 作为 UTF-8 / nul-terminated C string 输入时只在调用期借用。
- caller-owned buffer 必须使用 `out_required_len` 协议。
- 非 primitive 参数必须标注 `#borrow` 或明确 ownership。
- C 不能长期保存 MoonBit 指针。
- bridge v1 不使用 C callback 持有 MoonBit closure。

当前 proxy 层不需要新增 native ABI，也不需要 MoonBit native stub。
