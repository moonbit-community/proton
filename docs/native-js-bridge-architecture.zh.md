# Native/JS Bridge Architecture

本文档记录 Lepus 中 MoonBit/native 与 JavaScript 交互层的长期设计方向。它不是对当前实现的简单说明，而是把当前 `op` 机制的价值、限制、可优化方向，以及下一代架构规划整理成一份可以指导后续实现、评审和迁移的设计文档。

## 背景

Lepus 现在的 native/JS 通讯模式类似 Deno 的 op 机制：

- JavaScript 通过 `window.__MoonBit__.core.invokeOp(name, payload)` 调用 native 能力。
- `core` 在 native 侧维护 op registry，根据 op name 分发到 MoonBit handler。
- extension 通过 `ExtensionContext::op(...)` 和 `ExtensionContext::op_result(...)` 注册能力。
- JS-facing 扩展最终暴露为 `window.__MoonBit__.<extension>.*`。

这一层不是无意义的包装。它解决了 raw `webview.bind(...)` 的几个真实问题：

- 避免每个能力都占用一个全局 JS 函数。
- 给扩展提供 namespace。
- 统一 JSON 解码、错误返回、Promise 响应。
- 让扩展安装、事件、资源清理和多窗口生命周期可以进入同一套 runtime。
- 为 profiling、权限、资源追踪提供统一入口。

但是当前形态也有明显问题：

- `invokeOp("ext:path/resolve", ...)` 把内部 op name 暴露给用户心智。
- 每个 op 以字符串名字分发，适合调试，但不是长期最高效的 wire format。
- 大 payload 默认走 JSON，容易在文件、二进制、批量数组场景里成为瓶颈。
- 资源 id 目前更多由扩展内部管理，core 缺少全局 resource ownership 视角。
- 错误模型偏字符串，不利于 JS 侧处理、自动诊断和性能分析。
- 权限模型还停留在“是否安装某个扩展”的粒度，不能表达 path/root/action 等细粒度能力。

因此，推荐方向不是“去掉 op”，而是：

> 将 op 从用户可见 API 降级为 runtime 内部执行单元；对外提供生成式、typed、capability-aware 的扩展 API。

## 设计目标

### 用户体验

JavaScript 用户应该使用稳定、具体、可补全的 API：

```js
await window.__MoonBit__.fs.readTextFile("config.json");
await window.__MoonBit__.path.resolve(".");
await window.__MoonBit__.dialog.openFile({ title: "Open file" });
window.__MoonBit__.events.on("fs.activity", console.log);
```

用户不应该把底层 op name 当成主 API：

```js
// Debug-only / compatibility-only, not the preferred API.
await window.__MoonBit__.core.invokeOp("ext:fs/readTextFile", {
  path: "config.json",
});
```

### 扩展作者体验

扩展作者应该声明 method/command，而不是手写大量 bridge glue：

```moonbit
extension.method("readTextFile", read_text_file)
extension.method("open", open_file)
extension.event("activity", FsActivity)
```

实现层仍然可以映射到 op-like dispatch unit，但公开概念应该是 extension method 或 command。

### Runtime 能力

native/JS 边界必须天然支持：

- 统一 dispatch。
- typed payload/reply。
- Promise 风格异步。
- batch 调用。
- resource lifecycle。
- capability/permission check。
- structured error。
- op/method trace。
- 大数据 data plane。
- 多窗口隔离。

### 性能

性能目标不是把每个 native 调用伪装成普通 JS 函数，而是明确区分不同通信类型：

- 小控制消息：typed JSON。
- 高频小调用：batch。
- 长生命周期对象：resource id / handle。
- 大文本或二进制：buffer / shared buffer / chunked stream。
- 热路径 helper：generated client + numeric method id。

### 可维护性

架构应该让扩展能力在同一份 metadata 中服务多个用途：

- runtime dispatch。
- JS client 生成。
- TypeScript declaration 生成。
- manifest schema。
- capability policy。
- docs。
- tracing/profiling。
- catalog/tooling/AI diagnostics。

## 术语

| 术语 | 含义 | 用户可见 |
|---|---|---|
| Extension | 一组可选 native 能力，例如 `fs`、`path`、`dialog` | 是 |
| Method / Command | 扩展公开的一个操作，例如 `fs.readTextFile` | 是 |
| Capability | 权限能力，例如 `filesystem.read`、`dialog.openFile` | 部分可见 |
| Internal op | runtime 内部最小 dispatch 单元 | 否 |
| Method id / op id | build/runtime 分配给 method 的数字 id | 否 |
| Resource | native 长生命周期对象，例如 file handle、buffer、stream | 以 handle 形式可见 |
| Control plane | 小 JSON 请求/响应 | 否 |
| Data plane | buffer/resource/chunk 数据传输 | 否 |
| Trace event | profiling 与诊断事件 | debug 可见 |

## 当前架构评估

### 当前调用链

当前 JS 调用大致是：

```text
window.__MoonBit__.<extension>.<method>(payload)
  -> extension proxy/helper
  -> core.invokeOp("ext:<extension>/<method>", payload)
  -> __moonbit_op_dispatch({ name, payload })
  -> webview native binding
  -> OpRuntime::handle_request
  -> parse JSON request
  -> OpRegistry::call(name, payload)
  -> payload FromJson
  -> MoonBit handler
  -> reply ToJson/stringify
  -> webview.response
  -> JS Promise resolve/reject
```

### 当前机制的价值

这套机制相比 raw `webview.bind(...)` 有实际价值：

- 所有 extension 能力统一进入 `core`。
- namespace 可以避免全局函数污染。
- JSON decode/encode 和错误处理集中。
- op registry 提供了 profiling、permission、diagnostics 的自然挂点。
- `ExtensionHost` 可以统一处理安装、重复检测、namespace 保留、事件和 destroy hook。
- `ResourceTable` 为 `fs.open(...)` 这类能力提供了基本 handle 模型。

### 当前机制的风险

主要风险不是“有 op”，而是边界层还不够工程化：

- 用户 API 和内部 op name 的边界不清楚。
- 每次调用传字符串 op name，适合调试，不适合长期高性能 dispatch。
- 一切都走 JSON，导致大数据路径不健康。
- 错误是字符串，JS 侧无法稳定分支处理。
- resource 管理分散到扩展内部，core 缺少统一观测和泄漏检测。
- capability 粒度粗，难以安全支持远程页面或第三方扩展。

## Deno op 机制可借鉴点

Deno 的 op 值得借鉴的不是命名，而是 runtime 边界的工程化思想。

### 统一边界

Deno 将 JS 到 native/Rust 的系统能力集中到 op 层。这样 permissions、trace、resource 和 async 都可以在一个地方处理。

Lepus 应借鉴：

```text
所有 JS -> native 能力调用必须经过统一 dispatcher。
```

不要让扩展绕过 dispatcher 随意创建全局 JS binding，除非是非常底层、明确标记的 escape hatch。

### Promise / Future 对齐

Deno 的底层 binding 与 Promise/Future 对齐，天然支持 async/await。Lepus 也应该保持：

```js
await app.fs.readTextFile("a.txt");
```

而不是 callback-first API。

对于 stream，要优先设计拉取式 API：

```js
const file = await app.fs.open("big.log", "r");
const chunk = await file.read({ size: 65536 });
```

避免 native 无限制 push event，造成 JS 端背压失控。

### Resource 是一等对象

Deno 的 op 与 resource infrastructure 是一套系统。Lepus 应该把 resource 从“扩展内部的 rid map”升级为 core 可观测对象。

一个 resource 至少应记录：

```text
rid
type
owner_window
owner_extension
created_by_method
created_at
last_used_at
closed_at
metadata
```

### 权限绑定在 runtime 边界

Deno 默认拒绝大多数 I/O，需要显式授权。Lepus 不需要照搬 CLI flag，但应借鉴 capability policy：

```json
{
  "extensions": {
    "fs": {
      "read": ["$appData", "./assets"],
      "write": ["$appData"]
    },
    "dialog": true,
    "shell": false
  }
}
```

每次 method dispatch 前检查：

```text
window + extension + method + target path/resource/origin -> allowed?
```

### 可观测性内建

Deno 有 op tracing，可以看到 dispatch 和 complete 事件。Lepus 应该提供类似能力：

```js
window.__MoonBit__.core.setProfiler((event) => {
  console.log(event);
});
```

或 native 侧 trace sink：

```text
LEPUS_TRACE_OPS=1
LEPUS_TRACE_RESOURCES=1
```

## 推荐目标架构

推荐下一代模型：

```text
JavaScript generated client
  -> control/data transport
  -> numeric method id
  -> core dispatcher
  -> capability check
  -> typed decode
  -> extension handler
  -> structured reply/error
  -> resource tracker / event bus / profiler
```

### 分层

```text
app / bootstrap / manifest
  声明启用哪些扩展、窗口配置、extension options、capability policy

catalog / tooling
  读取 extension metadata
  生成 registry、JS client、类型声明、docs、schema、diagnostic hints

runtime
  管理 App、Window、窗口生命周期
  为每个 window 安装 kernel 与已选择 capability

core
  Transport: call / batch / response
  Dispatcher: method id -> typed handler
  CapabilityTable: window/method/resource policy
  ResourceTracker: native resource lifecycle
  EventBus: native -> JS event channel
  ErrorModel: structured errors
  Profiler: trace events

extensions/*
  声明 method/event/resource/capability metadata
  实现业务 handler
  不直接拥有公共 transport 协议
```

### 用户 API

推荐用户 API：

```js
const text = await app.fs.readTextFile("config.json");
const dir = await app.path.dirname("/tmp/a.txt");
const file = await app.fs.open("large.bin", "r");
const buffer = await app.buffers.alloc(64 * 1024);
const n = await file.readInto(buffer);
await file.close();
```

不推荐用户 API：

```js
await app.core.invokeOp("ext:fs/readTextFile", { path: "config.json" });
```

`invokeOp(name, payload)` 可以保留为：

- debug API。
- compatibility shim。
- custom experiment escape hatch。

但文档和示例不应把它作为主路径。

### 扩展 API

扩展作者应声明 method metadata：

```text
method:
  id: "readTextFile"
  js_name: "readTextFile"
  capability: "filesystem.read"
  payload: ReadTextFilePayload
  reply: ReadTextFileReply
  transport: "json"
```

对于 data plane：

```text
method:
  id: "readInto"
  capability: "filesystem.read"
  payload: ReadIntoPayload
  reply: ReadIntoReply
  transport: "buffer"
  resources:
    uses: ["fs.file", "buffer"]
```

### Internal op / method id

内部 dispatch 使用数字 id：

```text
17 -> fs.readTextFile
18 -> fs.writeTextFile
19 -> fs.open
20 -> fs.readInto
31 -> path.resolve
```

JS generated client 内部调用：

```js
return __lepus.call(17, { path });
```

低层 debug 映射可以保留：

```js
__lepus.debug.lookup("fs.readTextFile") // 17
__lepus.debug.nameOf(17)                // "fs.readTextFile"
```

### Transport

#### call

单次控制调用：

```js
__lepus.call(methodId, payload)
```

wire shape 可以是：

```json
[17, { "path": "config.json" }]
```

这比当前：

```json
[{ "name": "ext:fs/readTextFile", "payload": { "path": "config.json" } }]
```

更短、更稳定、更容易 batch。

#### batch

批量小调用：

```js
__lepus.batch([
  [31, { "path": "." }],
  [32, { "path": "/tmp/a.txt" }],
]);
```

batch 应保证：

- 返回顺序与请求顺序一致。
- 单个失败默认不取消其他调用，除非设置 `atomic: true`。
- trace 中保留 batch id 和每个 child method id。

#### stream/resource

长生命周期对象不直接返回大数据，而是返回 handle：

```js
const file = await app.fs.open("large.bin", "r");
const chunk = await file.read({ size: 65536 });
await file.close();
```

底层返回：

```json
{ "rid": 42, "type": "fs.file" }
```

#### buffer

大二进制或大文本使用 buffer：

```js
const buffer = await app.buffers.alloc(1048576);
const bytesRead = await app.fs.readInto(file, buffer, {
  offset: 0,
  length: buffer.byteLength,
});
```

实现上优先 shared buffer；不支持时 fallback 到 chunked transfer。

## 性能模型

### 主要成本来源

跨 native/JS 边界的成本通常来自：

1. webview binding 调用。
2. JSON stringify/parse。
3. 字符串和 buffer 拷贝。
4. Promise 调度。
5. handler 业务成本。

op name 字符串查表通常不是最大头，但它会在高频小调用里放大。

### 设计规则

#### 小控制消息可以走 JSON

适合：

- dialog 参数。
- path 单次查询。
- clipboard 文本。
- notification 配置。
- shell open 参数。

#### 高频小调用必须 batch

不应这样：

```js
for (const path of paths) {
  await app.path.dirname(path);
}
```

应提供：

```js
await app.path.dirnameMany(paths);
```

或通用：

```js
await app.core.batch([...]);
```

#### 大数据不能默认走 JSON

不应将几 MB 的文本、数组、二进制内容作为 JSON field 传来传去。

推荐：

- file/resource handle。
- chunked read/write。
- shared buffer。
- native buffer id。

#### path 这类纯计算 API 可以 JS 本地化

如果某些能力可以可靠地在 JS 端实现，并且不涉及 native state 或 OS 差异，可以考虑 JS helper 本地计算。

但 path API 涉及平台差异时，仍可保留 native canonical behavior，并提供 batch method 减少跨边界。

### 需要 benchmark 的维度

应建立基准：

- raw `webview.bind` noop。
- 当前 `invokeOp` noop。
- numeric id `call` noop。
- small JSON payload。
- medium JSON payload。
- large JSON payload。
- batch small calls。
- resource read/write。
- shared buffer read/write。
- JS helper proxy vs generated helper。

推荐输出：

```text
operation
count
mean_ms
p50_ms
p95_ms
p99_ms
payload_bytes
reply_bytes
alloc_estimate
```

## 可观测性

### Trace event

每个 method/op 调用应产生 trace：

```text
RpcTraceEvent {
  id
  parent_id?
  batch_id?
  window_id
  extension
  method
  method_id
  capability
  phase
  ok
  error_code?
  error_message?
  payload_bytes
  reply_bytes
  decode_ms
  permission_ms
  handler_ms
  encode_ms
  native_total_ms
  js_total_ms?
  resources_created
  resources_used
}
```

phase 至少包含：

```text
dispatch
complete
error
```

可选：

```text
decode_start
handler_start
handler_complete
encode_complete
```

### JS profiler API

推荐：

```js
const unsubscribe = app.core.setProfiler((event) => {
  console.log(event);
});
```

或：

```js
app.core.profiler.enable({
  methods: ["fs.*", "path.resolve"],
  includePayloadSize: true,
});
```

### Native trace sink

推荐支持：

```text
LEPUS_TRACE_METHODS=1
LEPUS_TRACE_RESOURCES=1
LEPUS_TRACE_OUTPUT=stderr | path/to/file.jsonl
```

JSONL event 便于后续工具读取。

### Debug UI

长期可以提供 debug 面板：

- 最近 N 次 method 调用。
- 慢调用排行。
- 每个 extension 的调用次数和耗时。
- resource 当前持有情况。
- resource 泄漏候选。
- permission denied 记录。

## Resource 管理

### ResourceTracker

core 应提供 ResourceTracker，扩展可以继续使用 typed `ResourceTable[T]` 保存实际值，但 resource lifecycle 必须登记到 core。

```text
ResourceTracker::open(type, owner, metadata) -> rid
ResourceTracker::touch(rid, method)
ResourceTracker::close(rid)
ResourceTracker::close_by_window(window_id)
ResourceTracker::snapshot()
```

### Resource metadata

文件资源示例：

```text
rid: 42
type: "fs.file"
owner_window: 1
owner_extension: "fs"
created_by_method: "fs.open"
created_at: ...
last_used_at: ...
closed_at: None
metadata:
  path: "C:/app/data/log.txt"
  mode: "r"
```

buffer 资源示例：

```text
rid: 73
type: "buffer"
owner_window: 1
created_by_method: "buffers.alloc"
metadata:
  byte_length: 1048576
  shared: true
```

### Lifecycle rules

- 关闭 window 时，释放该 window 拥有的所有 resource。
- 关闭 app 时，释放所有 resource。
- `ResourceTracker` 应记录未关闭资源，debug 模式下可以输出 warning。
- resource id 不应跨 window 默认共享。
- resource id 应与 capability 绑定，不能由任意 extension 随便使用。

### Resource 与 capability

使用 resource 时也要检查 capability：

```text
method fs.readInto(fileRid, bufferRid)
  -> fileRid must be fs.file
  -> fileRid owner window must match current window
  -> bufferRid must be buffer
  -> current method must be allowed to read fileRid
```

## 权限与 Capability

### 为什么需要

当前 `fs` 扩展一旦安装，就会给页面很大的文件系统能力。这对 trusted/local content 可以接受，但如果未来支持远程页面、第三方插件、动态内容或更复杂的多窗口模型，就不够安全。

### Capability policy

manifest 应表达能力而不是只表达安装：

```json
{
  "extensions": {
    "justjavac/lepus-fs": {
      "enabled": true,
      "permissions": {
        "read": ["$appData", "./assets"],
        "write": ["$appData"]
      }
    },
    "justjavac/lepus-shell": {
      "enabled": false
    }
  }
}
```

更短的兼容形式仍可支持：

```json
{
  "extensions": {
    "justjavac/lepus-path": true
  }
}
```

### Permission check

每次 method 调用前：

```text
resolve method metadata
resolve capability
resolve request target
check window policy
check resource ownership
allow or return structured PermissionDenied
```

### Deny 优先

建议支持 deny 规则，且 deny 优先于 allow：

```json
{
  "fs": {
    "read": ["$home"],
    "denyRead": ["$home/.ssh"]
  }
}
```

### 审计日志

debug 或 secure mode 下可以记录 permission audit：

```json
{
  "datetime": "2026-04-18T10:30:00Z",
  "window": "main",
  "extension": "fs",
  "method": "readTextFile",
  "permission": "filesystem.read",
  "value": "C:/app/data/config.json",
  "result": "allow"
}
```

## 错误模型

不要长期使用纯字符串错误。推荐：

```json
{
  "code": "ENOENT",
  "message": "No such file or directory",
  "details": {
    "path": "config.json"
  },
  "extension": "fs",
  "method": "readTextFile"
}
```

JS 侧错误对象：

```js
try {
  await app.fs.readTextFile("missing.txt");
} catch (error) {
  if (error.code === "ENOENT") {
    // stable handling
  }
}
```

推荐基础错误码：

```text
InvalidPayload
UnknownMethod
PermissionDenied
ResourceNotFound
ResourceClosed
Unsupported
IoError
Timeout
Cancelled
Internal
```

扩展可以定义自己的 code，但应保留稳定前缀或 namespace。

## Events

### Event bus

native -> JS 事件应统一走 event bus：

```js
app.events.on("fs.activity", handler);
app.fs.on("activity", handler);
```

事件也应该有 metadata：

```text
event:
  name: "activity"
  extension: "fs"
  payload: FsActivity
```

### 背压

事件适合通知，不适合大数据流。

不推荐：

```text
native emits "data" for every chunk without JS pulling
```

推荐：

```js
while (true) {
  const chunk = await stream.read({ size: 65536 });
  if (chunk.done) break;
}
```

事件可以通知 ready/state，而数据由 JS 主动 read。

## Extension metadata

每个 extension 应把下面内容作为 metadata 的一部分：

```text
id
namespace
version
methods[]
events[]
resources[]
capabilities[]
options_schema
js_client_strategy
```

method metadata 示例：

```json
{
  "name": "readTextFile",
  "jsName": "readTextFile",
  "capability": "filesystem.read",
  "transport": "json",
  "payload": "ReadTextFilePayload",
  "reply": "ReadTextFileReply",
  "creates": [],
  "uses": []
}
```

resource method 示例：

```json
{
  "name": "open",
  "jsName": "open",
  "capability": "filesystem.open",
  "transport": "json",
  "reply": "OpenReply",
  "creates": ["fs.file"]
}
```

buffer method 示例：

```json
{
  "name": "readInto",
  "jsName": "readInto",
  "capability": "filesystem.read",
  "transport": "buffer",
  "uses": ["fs.file", "buffer"]
}
```

## Generated client

动态 Proxy 适合早期原型，但长期应偏向生成式 client。

生成式 client 优点：

- JS API 明确。
- 更容易生成 TypeScript declaration。
- 更容易 tree-shake 或按扩展拆分。
- 性能更稳定。
- helper 可以使用 numeric method id。
- helper 可以自动 batch 或选择 data plane。
- 文档和示例可以从同一份 metadata 生成。

示例：

```js
export function installFs(root, kernel, ids) {
  root.fs = {
    async readTextFile(path, options) {
      return kernel.call(ids.fs_readTextFile, normalizeReadPayload(path, options))
        .then((reply) => reply.text);
    },
    async open(path, mode = "r") {
      const reply = await kernel.call(ids.fs_open, { path, mode });
      return new FileHandle(kernel, ids, reply.rid);
    },
  };
}
```

生成式 client 可以保留低层 escape hatch：

```js
root.fs.invoke = (method, payload) => kernel.invokeByName("fs", method, payload);
```

## Batch API

### 通用 batch

```js
const [cwd, configPath] = await app.core.batch([
  app.path.resolve.request("."),
  app.path.join.request("config", "app.json"),
]);
```

也可提供低层：

```js
await app.core.invokeBatch([
  { method: "path.resolve", payload: { path: "." } },
  { method: "path.dirname", payload: { path: "/tmp/a.txt" } },
]);
```

### 扩展专用 batch

扩展应提供语义化 batch：

```js
await app.path.resolveMany([".", "src", "examples"]);
await app.fs.statMany(["a.txt", "b.txt"]);
```

语义化 batch 通常比通用 batch 更好，因为 extension 可以优化内部实现。

## Data plane

### 为什么需要 data plane

JSON 对小对象很好，但对大文本、二进制和数组不是健康默认值。大 payload 会造成：

- JS stringify/parse 成本。
- native parse 成本。
- 字符串编码转换。
- 多次拷贝。
- GC 压力。

### 推荐 data plane 类型

```text
Resource handle:
  文件、stream、长期 native 对象

Shared buffer:
  大二进制、大数组、高吞吐读写

Chunked transfer:
  shared buffer 不可用时的 fallback

Memory-mapped or platform-specific handle:
  后续可选优化
```

### API 示例

```js
const file = await app.fs.open("large.bin", "r");
const buffer = await app.buffers.alloc(1024 * 1024);

let offset = 0;
while (true) {
  const { bytesRead } = await file.readInto(buffer, { offset: 0 });
  if (bytesRead === 0) break;
  process(buffer.slice(0, bytesRead));
  offset += bytesRead;
}

await buffer.close();
await file.close();
```

## 安全模型

### Trusted local content

如果页面是 app 自己打包的本地内容，安全边界可以相对简单，但仍建议 capability policy，以防 XSS 或第三方依赖被注入后扩大损害。

### Remote content

如果加载远程页面，应默认：

- 不安装高危 extension。
- 不授予 fs/shell/globalHotkey。
- 只允许明确声明的低风险 capability。
- 对 origin 做 policy 绑定。

示例：

```json
{
  "windows": {
    "docs": {
      "origin": "https://docs.example.com",
      "extensions": {
        "dialog": {
          "message": true,
          "openFile": false
        }
      }
    }
  }
}
```

### Shell 风险

`shell` 和 subprocess 类能力应被视为高危 capability。它们不应该因为 extension 安装就默认全开。

### File system 风险

`fs` 应支持 root allowlist：

```text
$appData
$cache
$resource
relative-to-manifest
explicit absolute path
```

并小心处理：

- symlink。
- path traversal。
- case-insensitive filesystem。
- Windows drive / UNC path。
- reserved system paths。

## 迁移路线

### Phase 0: 文档和原则

- 明确 `window.__MoonBit__.<extension>.*` 是主 API。
- 明确 `core.invokeOp(name, payload)` 是 debug/compat API。
- 文档中避免鼓励业务代码直接使用 internal op name。

### Phase 1: 低风险优化

- 批量注册 op names，减少启动期多次 script injection。
- path helper 使用现有 `joinAll` / `resolveAll`，避免循环跨边界。
- 增加 structured error 的内部类型，但保持旧字符串兼容。
- 在 `OpRuntime::handle_request` 和 `OpRegistry::call` 加 optional trace hook。

### Phase 2: Observability

- 增加 `OpTracer` / `MethodTracer`。
- 增加 JS profiler hook。
- 增加 trace JSONL 输出。
- 增加 payload/reply size 统计。
- 增加 slow method warning。

### Phase 3: ResourceTracker

- core 增加 ResourceTracker。
- fs 的 rid 注册到 core tracker。
- window destroy 时输出未关闭 resource。
- trace event 关联 resources_created/resources_used。

### Phase 4: Method metadata

- extension metadata 增加 methods/events/resources/capabilities。
- catalog/tooling 能读取 method metadata。
- 生成 method id table。
- 生成 JS client skeleton。

### Phase 5: Numeric dispatch

- 新增 `call(methodId, payload)`。
- `invokeOp(name, payload)` 变成 name -> methodId -> call。
- 保持旧 op registry 兼容。
- benchmark name dispatch vs numeric dispatch。

### Phase 6: Batch

- 新增 `batch(...)` transport。
- path/fs 增加语义化 batch API。
- profiler 支持 batch parent/child trace。

### Phase 7: Data plane

- buffers extension 或 core buffer API。
- shared buffer capability detection。
- fs readInto/writeFrom。
- fallback chunked transfer。

### Phase 8: Capability policy

- manifest 支持细粒度 capability options。
- dispatcher 执行 permission check。
- permission audit log。
- deny rules。

## 兼容策略

旧 API 不应突然删除：

```js
window.__MoonBit__.core.invokeOp(name, payload)
```

推荐迁移：

1. 保留 `invokeOp`。
2. 文档标为 low-level/debug。
3. 新 helper 内部不再依赖字符串 name。
4. trace event 对旧调用补齐 extension/method metadata。
5. 大版本再考虑 deprecation warning。

## 设计规则

1. 用户文档优先展示 extension method，不展示 internal op name。
2. 每个跨边界能力必须有 method metadata。
3. 每个 method 必须声明 capability。
4. 每个 resource 创建都必须登记 owner。
5. 大数据不得默认走 JSON。
6. 高频 API 必须提供 batch 或 coarse-grained 版本。
7. native -> JS 大数据不得靠无限事件推送。
8. 错误必须结构化。
9. profiling 不应是事后补丁，应是 dispatcher 的一等能力。
10. extension linking 继续保持显式，metadata 不等于自动链接。

## 非目标

短期不追求：

- 实现完整 Deno runtime。
- 引入 V8-only fastcall 机制。
- 让网页执行任意远程代码且自动安全。
- 为每个普通 JS 函数调用都进入 native。
- 用复杂 permission prompt 替代清晰 manifest policy。

## 参考资料

这些资料用于理解 Deno op 的工程价值，但 Lepus 不应照搬其用户可见模型：

- [Deno debugging: `--strace-ops`](https://docs.deno.com/runtime/fundamentals/debugging/)：Deno 将 op 作为 JS/Rust RPC 机制，并提供 dispatch/complete timing。
- [Deno security and permissions](https://docs.deno.com/runtime/fundamentals/security/)：Deno 默认拒绝 I/O，并通过 allow/deny/prompt/audit 管理能力。
- [deno_core `op2`](https://docs.rs/deno_core/latest/deno_core/attr.op2.html)：Deno 针对 V8 -> Rust 边界提供 fastcall、typed conversion、async 和 native object 支持。
- [Deno 1.0: Promises all the way down](https://deno.com/v1)：Deno 将底层 binding 与 Promise/Future 对齐，并把 op/resource 作为核心 runtime infrastructure。

## 推荐最终形态

一句话：

> Lepus 应该拥有 Deno op 的 runtime kernel 思想，但不应该暴露 Deno-like op 作为用户模型。

最终分工：

```text
用户看到:
  app.fs.readTextFile(...)
  app.path.resolve(...)
  app.dialog.openFile(...)

扩展声明:
  method / event / resource / capability metadata

runtime 内部:
  numeric method id
  dispatcher
  resource tracker
  capability table
  profiler

调试工具看到:
  op/method trace
  resource lifecycle
  permission audit
```

这样可以同时获得：

- 更干净的 JS API。
- 更小的跨边界开销。
- 更强的资源管理。
- 更好的性能分析。
- 更清晰的权限边界。
- 更容易维护的扩展生态。
