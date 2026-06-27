# Proton macOS Runtime 实施方案

## 0. 实施前置要求

**Before starting implementation:** Use the Skill tool to load the moonbit-c-binding skill, which provides comprehensive guidance on FFI declarations, ownership annotations, C stubs, and AddressSanitizer validation.

执行本文方案时还应先阅读当前仓库的 `AGENTS.md` 约束，尤其是：

- 不新增第二条 native 构建入口，`native/CMakeLists.txt` 仍是唯一 native
  build source of truth。
- 不把 CEF 暴露到 MoonBit 包名、C ABI 前缀或 public facade。
- 不禁用现有测试来换取 macOS 通过；只能按平台能力补齐测试环境或增加明确的
  engine-absent 分支。
- 不破坏已经成功运行的 Windows engine 路线。macOS 改造应以新增
  APPLE 分支、平台表和公共 helper 为主，不能改变 Windows runtime layout、
  manifest 字段含义或 `proton_engine_cef_win.c` 行为。

## 1. 目标

本文规划 Proton native runtime 的 macOS 实现。目标不是新增第二条
runtime 路线，而是在现有架构下补齐 macOS CEF engine：

```text
MoonBit app
  -> justjavac/proton
  -> justjavac/proton/native
  -> libproton.dylib
  -> CEF-backed native runtime
  -> CEF helper process
```

必须保持的不变量：

- MoonBit 用户代码只链接 Proton native library，不直接链接 CEF。
- CEF 仍是 native implementation detail，不进入 MoonBit 包名、C ABI
  前缀或用户 API。
- CMake 仍是 native 构建的唯一入口。
- `proton_*` C ABI 保持稳定，继续使用 `Int64` handle、JSON config、
  caller-owned buffer 和 status code。
- macOS 平台 id 使用 `darwin-arm64` 和 `darwin-x64`。
- `proton_cli cef setup` 负责组装 `.proton/runtimes/<platform>/...`，
  用户项目不手动摆放 CEF 文件。
- Windows 仍使用 `win32-x64`、`proton.dll`、`proton.lib`、
  `bin/cef_process.exe` 和现有 CEF runtime layout；macOS 不应要求 Windows
  用户迁移目录结构或命令。

第一阶段的成功标准：

1. macOS 上能构建 engine-backed `libproton.dylib`。
2. `native/dist` 能包含可运行的 Proton native runtime layout。
3. `RuntimeConfig::bundled().probe()` 在 macOS 通过。
4. `@proton.html(...).run_or_abort()` 能创建窗口并加载 `proton://app/`。
5. CDP e2e 至少跑通 `41_app_commands`。

第一阶段默认是开发态 runtime，不承诺签名后的 `.app` 分发。若 CEF 在
macOS 上要求 helper 以 `.app` bundle 形态启动，则 helper bundle 需要提前
进入 MVP；不能为了维持 `bin/cef_process` 形态而绕过 CEF 的进程模型。

## 2. 当前状态

当前代码已经具备良好的跨平台边界：

- `native/src/proton.c`
  - 平台无关 C ABI 外壳。
  - 负责 handle registry、JSON schema、runtime probe、事件队列和
    bridge queue。
  - 已经部分预留 macOS framework layout 探测。
- `native/src/proton_engine.h`
  - C ABI 外壳与具体 engine 的内部接口。
- `native/src/proton_engine_none.c`
  - ABI-only engine。
  - macOS 当前可用于接口测试，但不提供真实 GUI runtime。
- `native/src/proton_engine_cef_win.c`
  - 当前唯一真实 engine。
  - 负责 CEF 初始化、Win32 窗口、CEF browser、renderer bridge 和
    subprocess path。
- `proton/native_link_config.mjs`
  - 已经按非 Windows 平台生成 `-L... -lproton -Wl,-rpath,...`。
  - 已经按平台推导 `cef_process` / `cef_process.exe` helper 名称。
- `scripts/e2e_bridge_smoke.mjs`
  - 已有 CDP-based e2e runner。

主要缺口：

- `native/CMakeLists.txt` 中 `PROTON_WITH_ENGINE=ON` 只 wired 到 Windows。
- `proton_engine_cef_win.c` 混合了 CEF 通用逻辑和 Win32 平台逻辑，
  不适合直接复制成 mac 文件长期维护。
- `proton_cli cef setup` 当前只识别 Windows runtime。
- `native/scripts/verify_link_config.mjs` 目前只对 Windows helper 做强校验，
  macOS runtime 文件清单还需要补齐。
- `proton_default_helper_path` 当前默认 helper 名称偏 Windows。
- macOS 分发不是单 dylib 问题，需要处理 framework、helper bundle、
  `@rpath`、签名和 notarization。

## 3. 总体路线

推荐分两层推进：

1. 开发态 runtime dist。
   先让 `native/dist` 在 macOS 上可运行，用于本机验证、MoonBit 示例和
   CDP e2e。
2. 正式 app bundle 分发。
   在开发态能力稳定后，再落地 `.app`、helper app bundles、签名和
   notarization。

不要一开始就把完整 app bundle、签名、notarization 和 CEF bridge 全部
揉在一起。macOS 的失败面很宽，应该按 runtime probe、窗口、bridge、e2e、
bundle 的顺序收敛。

### 3.1 Windows 非回归策略

macOS 实施必须遵守以下保护线：

- `WIN32` 分支保持现有 CMake 行为：继续编译 `src/proton_engine_cef_win.c`，
  继续安装 `bin/cef_process.exe`、`bin/proton.dll`、`lib/proton.lib` 和现有
  CEF runtime 文件。
- CLI 的平台表只能增加 `darwin-arm64` / `darwin-x64`，不能改变
  `win32-x64` 的默认 CEF 名称、suffix、required file 清单和 manifest 字段。
- `native_link_config.mjs` 对 Windows 的 `link_libs`、`PROTON_HELPER_PATH`
  和 `Path`/runtime dir 行为保持不变。
- 抽公共层时先移动无平台依赖的纯 helper；涉及 bridge、scheme、renderer
  行为的提取必须用 Windows e2e 兜底。若没有 Windows 验证环境，该 PR 不应
  重构 Windows engine 大块逻辑。
- macOS 专属问题使用 `#ifdef __APPLE__`、APPLE CMake 分支或平台清单解决，
  不把 macOS framework/helper bundle 假设扩散到 Windows 代码路径。

## 4. Native 构建改造

### 4.1 CMake 平台选择

`native/CMakeLists.txt` 当前 `project(proton_native C)` 只启用 C。macOS
engine 需要 Objective-C 文件时，应将 engine source 改为显式平台选择，并在
APPLE 分支启用 `OBJC`：

```cmake
if(PROTON_WITH_ENGINE)
  if(WIN32)
    set(PROTON_ENGINE_SOURCE src/proton_engine_cef_win.c)
  elseif(APPLE)
    enable_language(OBJC)
    set(PROTON_ENGINE_SOURCE
      src/proton_engine_cef_common.c
      src/proton_engine_cef_mac.m
    )
  else()
    message(FATAL_ERROR "PROTON_WITH_ENGINE is not wired for this platform")
  endif()
endif()
```

如果短期不拆公共层，也可以先用单文件
`src/proton_engine_cef_mac.m` 实现 MVP。但正式方案应抽公共层，避免
Windows 和 macOS 各自维护一份 bridge 和 scheme handler。

`cef_process` target 也应从 Windows 分支移到 engine 通用分支；平台分支只
负责可执行文件后缀、bundle 形态和 install layout。移动 target 时必须确认
Windows install 结果仍是 `native/dist/bin/cef_process.exe`，不能因为通用化
改变现有 Windows 发布包内容。

### 4.2 macOS CEF SDK 校验

macOS CEF root 建议支持 SDK layout：

```text
cef_binary_*_macos*_minimal/
  include/
  Release/
    Chromium Embedded Framework.framework/
      Chromium Embedded Framework
  Resources/
    icudtl.dat
    locales/
    *.pak
```

部分 CEF framework bundle 也会带 `Resources` 目录；CMake 和 native probe
可以兼容该形态，但 source SDK 校验不要只写死 framework 内部资源路径。

CMake configure 时至少校验：

- `include/capi/cef_app_capi.h`
- `include/capi/cef_browser_capi.h`
- `include/capi/cef_client_capi.h`
- `include/capi/cef_v8_capi.h`
- `Release/Chromium Embedded Framework.framework/Chromium Embedded Framework`
- `Resources/icudtl.dat` 或
  `Release/Chromium Embedded Framework.framework/Resources/icudtl.dat`
- `Resources/locales` 或
  `Release/Chromium Embedded Framework.framework/Resources/locales`

### 4.3 macOS 链接

`proton` 需要链接：

- `Chromium Embedded Framework.framework`
- `Cocoa`
- `Foundation`
- `AppKit`
- `objc` 或 CMake 对 Objective-C runtime 的等价链接

并设置 runtime search path：

```cmake
find_library(PROTON_CEF_FRAMEWORK
  NAMES "Chromium Embedded Framework"
  PATHS "${PROTON_ENGINE_FRAMEWORK_PARENT}"
  NO_DEFAULT_PATH
)

target_link_libraries(proton PRIVATE
  "${PROTON_CEF_FRAMEWORK}"
  "-framework Cocoa"
  "-framework Foundation"
  "-framework AppKit"
)

set_target_properties(proton PROPERTIES
  INSTALL_RPATH "@loader_path/../Frameworks;@loader_path"
)
target_link_options(proton PRIVATE
  "-F${PROTON_ENGINE_FRAMEWORK_PARENT}"
)
```

`libproton.dylib` 的 install name 应稳定指向 `@rpath/libproton.dylib`
或适合当前 dist 的 loader path。后续 app bundle 阶段再用
`install_name_tool` 收敛到最终 bundle layout。

### 4.4 开发态 install layout

第一阶段建议安装到：

```text
native/dist/
  bin/
    cef_process
  lib/
    libproton.dylib
  include/
    proton_native.h
  Frameworks/
    Chromium Embedded Framework.framework
  Resources/
    icudtl.dat
    locales/
    *.pak
```

这里的 `Resources/` 可以从 framework resources 复制，也可以在 native
probe 中允许 `Frameworks/Chromium Embedded Framework.framework/Resources`
作为默认资源位置。为了和现有 Windows dist 规则接近，推荐 install 时显式
复制到 `native/dist/Resources`。如果 source SDK 是根级 `Resources/`，
install 直接复制该目录；如果资源只存在于 framework bundle 内，则从
framework resources 复制。

需要在 M2 做一个 helper 形态 spike：

- 如果 CEF 允许裸 executable，开发态先使用 `bin/cef_process`。
- 如果 CEF 在 macOS 上要求 app bundle，则开发态 dist 也使用最小
  `Contents/Helpers/Proton Helper.app/...`，并让 `helper_path` 指向 bundle
  内的 executable。

## 5. CEF Engine 代码组织

### 5.1 推荐拆分

长期维护结构：

```text
native/src/proton_engine_cef_common.h
native/src/proton_engine_cef_common.c
native/src/proton_engine_cef_win.c
native/src/proton_engine_cef_mac.m
```

公共层保留：

- CEF C API include 和 API hash 检查。
- `cef_string_t` / UTF-8 转换。
- CEF ref-counted base 初始化。
- JSON config helper。
- bridge op allowlist。
- bridge request queue。
- pending response map。
- `proton://` scheme handler。
- load handler 和 bridge injection。
- renderer process handler / V8 handler。
- `poll_bridge_request_json` 和 `respond_bridge_request_json`。

平台层保留：

- runtime root 和 helper path 推导。
- `cef_main_args_t` 初始化。
- platform message loop pump。
- platform window create/show/hide/focus/resize/close。
- browser parent view/window_info 配置。
- CEF framework/DLL 路径差异。

### 5.2 短期 MVP 取舍

如果拆公共层成本过高，MVP 可以先新增 `proton_engine_cef_mac.m`，复用
Windows 文件中的 bridge 逻辑。但必须在 PR 中明确这是临时状态，并列出后续
公共层拆分任务。否则 bridge 修复会在两个大文件中重复发生。

更稳妥的折中是先抽出纯 C、无平台窗口依赖的最小公共层，例如字符串转换、
bridge op allowlist、scheme response builder 和 JSON helper。窗口和
message pump 仍分别落在 `*_win.c` / `*_mac.m`。

## 6. macOS CEF Runtime 初始化

### 6.1 `cef_main_args_t`

macOS 不使用 Windows `HINSTANCE`。应通过 `_NSGetArgc()` 和 `_NSGetArgv()`
初始化：

```c
cef_main_args_t args;
memset(&args, 0, sizeof(args));
args.argc = *_NSGetArgc();
args.argv = *_NSGetArgv();
```

### 6.2 `cef_settings_t`

建议初始配置：

- `settings.no_sandbox = 1`
- `settings.multi_threaded_message_loop = 0`
- `settings.external_message_pump = 1`
- `settings.remote_debugging_port = config.remote_debugging_port`
- `settings.browser_subprocess_path = config.helper_path`
- `settings.framework_dir_path = runtime_root/Frameworks/Chromium Embedded Framework.framework`
- `settings.root_cache_path = config.cache_dir`，没有传入时创建可写临时目录

macOS 测试建议加入 command-line switch：

- `use-mock-keychain`
- 必要时保留 `disable-gpu` 作为调试开关，但不要把所有调试开关固化为生产默认。

`use-mock-keychain` 对 CI 和本地自动化很重要，可以避免 CEF 初始化期间卡在
Keychain 访问。

### 6.3 `cef_execute_process`

`cef_process` helper 的 `main` 仍调用：

```c
proton_execute_process("{\"abi_version\":1,\"use_bundled\":true}", &exit_code)
```

macOS 下 `use_bundled=true` 必须能从已加载的 `libproton.dylib` 或 helper
位置推导 runtime root。短期开发态可让 helper 与 `libproton.dylib` 共用
`native/dist`；正式 bundle 阶段需要从 app bundle 路径推导。

## 7. Cocoa Window 和 Message Pump

macOS 窗口层建议使用 Objective-C `.m` 文件实现，不建议继续用纯
`objc_msgSend` 拼所有 AppKit 调用。这样更符合 C 项目常规，也更容易调试
delegate 生命周期。

### 7.1 NSApplication 初始化

runtime create 阶段确保：

- `[NSApplication sharedApplication]`
- `setActivationPolicy:NSApplicationActivationPolicyRegular`
- `finishLaunching`

所有 AppKit 调用必须发生在 runtime owner thread。现有 native 层已经有
owner-thread 约束，macOS 实现要继承这个约束，不允许从任意 CEF 线程直接
操作窗口。

### 7.2 NSWindow

window create 应完成：

- 创建 `NSWindow`，保存到 `proton_engine_window_t`。
- 设置 title、content size、delegate。
- `contentView` 作为 CEF browser parent view。
- show/hide/focus/resize/close 分别映射到 AppKit API。

窗口关闭策略：

1. 用户点击关闭。
2. delegate 拦截 `windowShouldClose:`
3. 如果 browser 存在，调用 `cef_browser_host_t.close_browser`。
4. CEF `on_before_close` 后标记 window closed。
5. native event queue 发出 `window_closed`。

不要只关闭 NSWindow 而不关闭 CEF browser；否则 MoonBit pump 可能等不到
关闭事件。

### 7.3 CEF browser view

创建 browser 时：

- `window_info.parent_view = window->content_view`
- `window_info.bounds = {0, 0, width, height}`
- `window->browser_view = window_info.view`

resize 时同步：

- NSWindow content size
- contentView frame
- browser view frame

### 7.4 Message pump

`proton_engine_runtime_do_message_loop_work` 在 macOS 应做两件事：

1. drain Cocoa events。
2. 调用 `cef_do_message_loop_work()`。

伪代码：

```objc
for (;;) {
  NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                      untilDate:[NSDate distantPast]
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES];
  if (event == nil) {
    break;
  }
  [NSApp sendEvent:event];
}
[NSApp updateWindows];
cef_do_message_loop_work();
```

这与当前 facade 的 cooperative pump 匹配：MoonBit 侧仍通过
`runtime.do_message_loop_work()` 驱动 native runtime。

## 8. Runtime Layout 和 Probe

### 8.1 Helper path

`proton_default_helper_path` 需要平台化：

- Windows：`bin/cef_process.exe`
- macOS 开发态：`bin/cef_process`
- macOS bundle 态：helper app bundle 内 executable

MVP 可以先验证 `bin/cef_process`，但这不是架构承诺。若 CEF/macOS signing
要求 helper bundle，则 MVP helper path 应直接切到：

```text
Contents/Helpers/Proton Helper.app/Contents/MacOS/Proton Helper
```

### 8.2 Framework path

`proton_find_engine_library` 已有 macOS 预留，但需要更严格：

- 允许 `runtime_root/Chromium Embedded Framework.framework`
- 允许 `runtime_root/Frameworks/Chromium Embedded Framework.framework`
- 校验 framework binary：
  `Chromium Embedded Framework.framework/Chromium Embedded Framework`

仅检查 framework 目录不够，目录存在但 binary 缺失时运行期会失败。

### 8.3 Resources path

默认资源路径顺序建议：

1. config 显式 `resources_dir`
2. `runtime_root/Resources`
3. `runtime_root/Frameworks/Chromium Embedded Framework.framework/Resources`

必须检查：

- `icudtl.dat`
- `locales/`
- CEF required `.pak` / snapshot 文件

### 8.4 Runtime manifest

`.proton/runtime.json` 在 macOS 应包含：

```json
{
  "platform": "darwin-arm64",
  "dist": ".proton/runtimes/darwin-arm64/proton-.../",
  "runtime_root": ".proton/runtimes/darwin-arm64/proton-.../",
  "helper_path": ".proton/runtimes/darwin-arm64/proton-.../bin/cef_process"
}
```

如果 MVP 采用 helper app bundle，`helper_path` 应指向 bundle 内 executable，
而不是 `.app` 目录本身。

字段名保持现有 link config 可消费。不要让 MoonBit 用户代码感知 CEF SDK
路径。`native_link_config.mjs` 已经会读取 active `.proton/runtime.json` 的
`dist` 字段，并在非 Windows 平台生成 `-L`、`-lproton` 和 rpath；macOS
工作重点是保证 CLI 写出的 manifest 与实际 dist layout 一致。

## 9. `proton_cli cef setup`

CLI 需要从 Windows-only 改为平台表驱动。

### 9.1 平台识别

`current_platform()`：

- Windows x64：`win32-x64`，CEF suffix `_windows64_minimal`
- macOS arm64：`darwin-arm64`，CEF suffix `_macosarm64_minimal`
- macOS x64：`darwin-x64`，CEF suffix `_macosx64_minimal`

不能只靠 `@path.sep` 判断平台；它只能区分 Windows 路径风格。CLI 需要同时
识别 OS 和 CPU arch。若 MoonBit 标准库当前没有直接暴露 arch，应通过现有
命令执行能力读取 `uname -m` / 环境变量，或者在 CLI 层引入一个小的
platform probe helper。

### 9.2 Path helper

当前 CLI path helper 偏 Windows。应改成平台分隔符，或新增一个统一 helper：

```moonbit
fn path_sep() -> String {
  if @path.sep == '\\' { "\\" } else { "/" }
}
```

所有 required file 列表也应使用平台 path join 生成，不要在字符串里写死
反斜杠。

### 9.3 平台文件清单

Windows 清单继续保持现状。macOS 清单单独维护：

```text
lib/libproton.dylib
bin/cef_process
include/proton_native.h
Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework
Resources/icudtl.dat
Resources/locales
```

后续 bundle 阶段再扩展 helper app bundles 和 Info.plist。

`verify_link_config.mjs` 也应增加同一份 macOS 必要文件校验，至少覆盖：

- `lib/libproton.dylib`
- `bin/cef_process` 或 helper bundle executable
- `include/proton_native.h`
- CEF framework binary
- `Resources/icudtl.dat`
- `Resources/locales`

## 10. App Bundle 分发

开发态 dist 跑通后，再做正式 macOS app bundle。

目标布局：

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
      Proton Helper.app
      Proton Helper (Renderer).app
      Proton Helper (GPU).app
    Resources/
```

必须处理：

- `@rpath`
- `install_name`
- helper app bundle id
- `Info.plist`
- code signing
- hardened runtime
- notarization
- CEF framework resources

这部分不建议混入首个 macOS engine PR。可以作为 M8 单独交付。

## 11. 测试计划

### 11.1 ABI-only 不回归

```sh
cmake -S native -B native/build -DCMAKE_INSTALL_PREFIX=native/dist
cmake --build native/build
cmake --install native/build
ctest --test-dir native/build --output-on-failure
moon -C proton test native --target native --diagnostic-limit 80
```

这些测试不应因为 macOS engine work 被禁用。若某个测试需要真实 engine，
应通过现有 config/probe 机制区分 engine-present 和 ABI-only，而不是跳过
整组 native tests。

### 11.2 macOS engine build

```sh
cmake -S native -B native/build-engine \
  -DCMAKE_INSTALL_PREFIX=native/dist \
  -DPROTON_WITH_ENGINE=ON \
  -DPROTON_ENGINE_ROOT=.cef-cache/cef_binary_*_macosarm64_minimal
cmake --build native/build-engine
cmake --install native/build-engine
ctest --test-dir native/build-engine --output-on-failure
```

### 11.3 Link config 和 probe

```sh
node native/scripts/verify_link_config.mjs native/dist
PROTON_NATIVE_DIST=$PWD/native/dist moon -C proton test native --target native
```

### 11.4 示例 smoke

```sh
PROTON_NATIVE_DIST=$PWD/native/dist moon -C examples run 37_native_mvp --target native
PROTON_NATIVE_DIST=$PWD/native/dist moon -C examples run 43_native_bind_smoke --target native
```

### 11.5 CDP e2e

最小闭环：

```sh
PROTON_NATIVE_DIST=$PWD/native/dist node scripts/e2e_bridge_smoke.mjs 41_app_commands
```

扩展场景：

```sh
PROTON_NATIVE_DIST=$PWD/native/dist node scripts/e2e_bridge_smoke.mjs \
  38_async_extension_add 39_sync_async_extensions
PROTON_NATIVE_DIST=$PWD/native/dist node scripts/e2e_bridge_smoke.mjs \
  40_event_broadcast
PROTON_NATIVE_DIST=$PWD/native/dist node scripts/e2e_bridge_smoke.mjs \
  42_attribute_codegen_commands 45_bridge_multi_window
```

CI 上可以先只跑 build/probe。GUI e2e 如果 GitHub macOS runner 不稳定，
应放到 self-hosted mac runner 或手工验收脚本中。

### 11.6 Windows 回归基线

任何会触碰 CMake、CLI、link config、CEF 公共层或 bridge 逻辑的 PR，都要在
Windows 上跑现有成功路径。基线命令保持当前仓库说明：

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
ctest --test-dir native\build-engine -C Debug --output-on-failure
node native\scripts\verify_link_config.mjs native\dist
moon -C cli run . -- -C .. cef setup
moon -C proton test native --target native --diagnostic-limit 80
moon -C proton check --target native --diagnostic-limit 80
moon -C examples build --target native --diagnostic-limit 80
moon -C cli test --target native --diagnostic-limit 80
node .\scripts\e2e_bridge_smoke.mjs 41_app_commands
```

如果当前开发机不是 Windows，PR 描述必须明确标注 Windows 回归由谁、在哪个
环境补跑；不能用“macOS 已通过”替代 Windows 验收。

## 12. 里程碑

### M1：CMake 和 CLI 平台入口

- `PROTON_WITH_ENGINE=ON` 在 macOS 不再 configure-time fail。
- CLI 识别 `darwin-arm64` / `darwin-x64`。
- macOS required file 清单独立于 Windows。

验收：

- ABI-only CI 不回归。
- Windows engine configure/build/install 不回归。
- macOS engine configure 能明确报告缺失文件，错误信息可读。

### M2：开发态 native dist

- 构建 `libproton.dylib`。
- 构建 `bin/cef_process`，或在 spike 证明必须时构建最小 helper app
  bundle。
- install CEF framework、resources、header 到 `native/dist`。

验收：

- `node native/scripts/verify_link_config.mjs native/dist` 通过。
- `RuntimeConfig::bundled().probe()` 通过。
- Windows `verify_link_config.mjs native\dist` 和 `cef setup` 行为不变。

### M3：CEF runtime 初始化

- `proton_execute_process` 能处理 subprocess。
- `proton_runtime_create_json` 能初始化 CEF。
- `proton_runtime_destroy` 能干净释放。

验收：

- native smoke test 覆盖 create/destroy。
- 没有 Keychain 卡死。
- Windows runtime create/destroy smoke 不回归。

### M4：Cocoa window 和 browser

- 创建 NSWindow。
- 创建 CEF browser view。
- show/hide/focus/set_title/set_size 可用。
- close 事件正确进入 native event queue。

验收：

- `37_native_mvp` 能打开和关闭窗口。
- Windows `37_native_mvp` 行为不回归。

### M5：HTML、scheme 和 bridge

- `load_html(..., "proton://app/")` 可用。
- `proton://` scheme handler 可用。
- bridge 只注入 `proton://` 页面。
- unknown op、oversized payload、queue full 保持现有安全策略。

验收：

- `43_native_bind_smoke` 通过。
- `41_app_commands` CDP e2e 通过。
- Windows `41_app_commands` CDP e2e 不回归。

### M6：全 bridge e2e

- async extension、sync extension、event broadcast、attribute codegen、
  multi-window bridge 场景通过。

验收：

- `scripts/e2e_bridge_smoke.mjs` 全场景通过。
- Windows 同一组 e2e 不回归。

### M7：公共层整理

- Windows 和 macOS 不再重复维护 bridge/scheme/renderer 大块逻辑。
- 公共层和平台层边界清晰。

如果 M5/M6 为了抢通 MVP 临时复制了 bridge 逻辑，则 M7 应在继续扩展更多
bridge 能力之前完成，避免两个平台行为漂移。

验收：

- Windows e2e 不回归。
- macOS e2e 不回归。

### M8：app bundle 分发

- `.app` layout、helper app bundle、signing、notarization 方案落地。
- 文档更新到用户可执行步骤。

验收：

- 签名后的 app 在干净 macOS 机器上可运行。

## 13. 风险和应对

### AppKit 主线程约束

风险：从非 owner thread 操作 AppKit 会出现随机崩溃或无响应。

应对：所有 public runtime/window API 继续要求 owner thread；CEF callback 中
只更新 thread-safe queue，不直接调用 MoonBit 或 AppKit。

### CEF helper bundle

风险：开发态 `bin/cef_process` 能跑，但正式签名 app 需要 helper app bundle。

应对：MVP 明确只承诺开发态 dist；bundle 作为 M8 单独交付。

### Framework 和 `@rpath`

风险：链接成功但运行时 loader 找不到 framework 或 `libproton.dylib`。

应对：CMake install 后运行 `otool -L` 检查；`verify_link_config` 增加 macOS
runtime 文件和 rpath 校验。

### Keychain / sandbox

风险：CEF 初始化在 CI 或自动化测试中卡住。

应对：测试环境默认追加 `use-mock-keychain`；生产 sandbox 策略另行设计。

### Window close 时序

风险：NSWindow 已关闭，但 CEF browser 没完成 close，MoonBit pump 不退出。

应对：delegate 拦截用户关闭，先请求 CEF close；`on_before_close` 统一标记
window closed 并清理 pending bridge。

### 复制 Windows 大文件

风险：`proton_engine_cef_win.c` 直接复制出 mac 文件，后续 bugfix 要双写。

应对：MVP 可临时复制，但 M7 必须抽公共层；任何 bridge 修复优先落到公共层。

### Windows 行为漂移

风险：为 macOS 抽 CMake/CLI/bridge 公共层时，误改 Windows runtime layout、
helper 路径、manifest 字段或 bridge 时序。

应对：Windows 分支先保持行为等价；公共层提取分小 PR 完成，每个 PR 都跑
Windows build、probe、MoonBit native tests 和至少 `41_app_commands` e2e。

## 14. 非目标

本计划不包含：

- WebView2 / WKWebView / WebKitGTK 多后端抽象。
- MoonBit 用户直接链接 CEF。
- 恢复旧 `webview_*` C ABI。
- 远程 URL 默认暴露 bridge。
- 多 runtime bridge 协调。
- streaming op 或 binary payload。
- 第一阶段完成 notarization。

## 15. 建议执行顺序

1. 先改 CMake 和 CLI 平台入口。
2. 增加 macOS runtime probe 和 `verify_link_config` 校验。
3. 做 macOS CEF 初始化，无窗口 create/destroy。
4. 做 Cocoa window 和 browser view。
5. 接 `proton://` scheme 和 HTML load。
6. 接 bridge injection 和 request/response。
7. 跑 CDP e2e。
8. 抽 CEF 公共层。
9. 做 app bundle/signing/notarization。

这条路线的核心是先证明当前 Proton ABI 和 facade 不需要改变。只要
`libproton.dylib` 能按现有 ABI 提供同等行为，MoonBit 层和用户 API 都可以
保持稳定。同时，Windows 已经成功运行的 `proton.dll` 路线应作为基线持续
保护，macOS 的新增能力不能要求 Windows 用户改变任何现有使用方式。
