# Release Notes

## 未发布

**项目创建**

`proton_cli new` 改为调用 `moon-new`，从 Proton 的 `main` 分支下载所选模板。
保留目标路径、`--template` 和 `--author`；创建时不再提问或执行 `moon check`。
Git 初始化遵循 moon-new 的行为。

也可以直接使用 `moonx moonbit-community/moon-new` 创建项目，指定
`--template moonbit-community/proton --branch main`，再用
`--subdir templates/minimal` 或 `--subdir templates/isomorphic` 选择模板。
用 `--user` 代替 CLI 的 `--author`。

移除旧的标题、标识、窗口尺寸、检查、Git、预览和确认选项，改为编辑生成的配置与源码，
并显式运行检查。参见 [new 命令](../command-line-interface/commands.md#new)。

## 0.6.0

0.6.0 新增运行时创建窗口和带鉴权的文件下载，将剪贴板及休眠抑制 API 改为异步操作，并修复 Windows 监听问题。使用相关 API 的已有应用需要按下文迁移。

**运行时创建窗口（破坏性 API 变更）**

`WindowManager.create(id, config)` 可以在运行时使用可复用的 `WindowConfig` 创建独立窗口，包括单实例应用内的多个窗口。窗口 ID 不再需要预先声明。各实例拥有独立的子视图、命令来源身份和清理作用域；复用 ID 后旧句柄仍然无效。

将 `windows.open(id)` 替换为 `windows.create(id, config)`。删除延迟打开的 `add_window(..., open_on_start=false)` 声明，将配置保留在创建位置。`App.add_window(id, config)` 仍用于启动时创建窗口；`open_on_start` 和 `UnknownWindow` 已移除。使用 `RendererTarget::entry_prefix` 或 `bundled_prefix` 明确授权一组 ID，也可以继续按精确 ID 授权。

`NewWindowDecision::OpenInWindow(id)` 现在只操作已有实例。需要创建实例的新窗口处理器必须先等待 `create`。参见[窗口管理](../introduction/application-api.md#窗口与浏览器视图)和[多窗口示例](../examples/45_bridge_multi_window.md)。

**Windows 屏幕监听**

修复启动屏幕监听后收不到显示器分辨率变化通知的问题。监听无需可见的应用窗口。

**带鉴权的文件下载**

`moonbit-community/proton_ext/net` 包新增后端异步函数
`download(url, destination, headers?, overwrite?, on_progress?)`。
应用可以携带 `Authorization` 请求头下载二进制文件，无需将完整响应放入内存，
也无需通过 IPC 传输文件内容。

下载支持进度通知和任务取消。目标文件的父目录必须存在；只有显式设置
`overwrite=true`，才会在新内容完整保存后替换已有文件。
目标路径保留 POSIX 下符号链接后接 `..` 的遍历含义，以及 Windows 目录联接和显式扩展
路径前缀。覆盖最终符号链接时替换链接本身，不修改其目标文件。
函数正常返回表示保存成功，失败抛出 `DownloadError`。
只接受 HTTP 200，不支持重定向和部分下载。在上游 HTTP 解码问题修复前，
下载默认请求 identity 编码，并拒绝压缩响应；服务端必须返回未编码的内容。

该功能不会为 `net.capability()` 增加前端命令或文件写入权限，
也不改变浏览器下载接口 `WebContentsHandle.download_url()` 的行为。
用法和取消语义见[宿主网络](../introduction/application-api.md#扩展与能力)。

**休眠抑制生命周期**

Linux keep-awake 现在等待明确取得休眠抑制后才成功，不再把辅助进程存活视为已取得锁。
获取和清理采用异步等待；辅助进程退出后不再报告保护仍然 active。

直接使用 `proton_keepawake` 时，需要向异步 `acquire(tasks, ...)` 传入拥有其生命周期
的任务组，并在异步上下文调用 `release()`。`with_keepawake` 改为接收异步回调，
作用域结束时释放保护；Linux 辅助进程意外退出时取消回调并报错。前端扩展命令保持
不变，由扩展自动管理生命周期。参见[休眠抑制用法](../introduction/application-api.md#扩展与能力)。

**剪贴板访问（破坏性 API 变更）**

直接使用 `proton_clipboard` 时，必须在异步上下文调用 `read_text()` 和 `write_text(text)`。返回值仍为 `Result`：操作失败返回 `Err(String)`，取消通过异步运行时传播。前端扩展命令保持不变。

macOS 使用原生剪贴板。Linux 继续使用 `wl-clipboard`、`xclip` 或 `xsel`，管道读写和进程等待现在会让出事件循环。取消会停止并回收被调用的工具；写入成功后保留供后续粘贴使用的剪贴板所有者进程。

**Windows 电源监听**

交流电和内置电池通知现在正确产生 `OnAC` 和 `OnBattery`，UPS 和未知电源不再产生误导事件。32 位最后输入计数器回绕后，空闲时间查询不再将系统运行时间的高位计入空闲时长。计数器仍无法区分跨越完整周期（约 49.7 天）的空闲间隔。

**升级要求**

0.6.0 发布后，将 CLI 和应用的 `proton_*` 依赖一起升级。按上述说明迁移窗口创建及直接调用的剪贴板／休眠抑制接口，执行 `proton_cli cef setup`，再使用匹配的 helper 重新打包应用。MoonBit `latest` 工具链要求和 CEF 版本不变。安装 CLI 不会改写已有应用源码。

[完整改动](https://github.com/moonbit-community/proton/compare/c63c9d2963551802481f4b2f13094afcce9222a5...91ffc6210878af84a639d773efdc71669dc47430)

## 0.5.1

0.5.1 修复资源加载、文件系统链接操作、监听启动和更新 manifest 解析，补全 macOS／Linux shell 操作，并提供公共 Rabbita 查询包。虽然版本号只增加 patch，直接使用电源监听、shell 和 updater 模块的应用仍需按下表迁移源码。

**API 变化与迁移**

| 范围 | 原 API | 0.5.1 |
| --- | --- | --- |
| 电源事件监听 | `start_watching()` / `stop_watching()` | 在异步 `with_watching(callback)` 中执行需要事件的工作。返回、抛错或取消会结束监听并等待清理；作用域结束后才能调用 `destroy()` |
| 原生 shell 操作 | 同步 `open`、`reveal_item`、`trash_item`，返回 `Result` | 在异步上下文调用；成功返回 `Unit`，失败抛出 `ShellError`。`beep()` 不变 |
| Manifest 解析 | `Manifest::from_json(Json)` | 将原始文档文本传给 `Manifest::parse(text)`，保留整数精度 |

Proton 电源监听扩展自动管理监听作用域。其 `watch_status()` 新增 `Starting`，穷尽匹配该状态的代码需要更新。Linux 启动可在连接、认证或订阅期间取消，并有五秒期限。总线断开会结束作用域，不再留下“正在监听”的状态。详见[能力契约](../introduction/application-api.md#扩展与能力)。

新建 isomorphic 项目直接导入 `moonbit-community/proton_rabbita/query`，不再生成 `frontend/internal/query`。已有项目可将本地包的导入替换为公共包，检查本地定制后删除原实现。`create`、`state`、`set_input` 和 `refresh` 的用法不变。该包管理组件读取、订阅和取消，不提供共享缓存或自动重试。[Isomorphic 教程](../tutorial/isomorphic.md)

**行为变化与修复**

- **HTML 资源：** `file` 和 `asset` 在 `https://proton.localhost/` 下按文件名提供原始文档，以入口目录作为资源根目录，相对资源遵循浏览器的 URL 解析规则。Proton 不再改写 HTML 或插入 `<base>`；需要指定 base 时应在文档中声明。构造函数不变。[入口来源](../introduction/application-api.md#应用生命周期)
- **文件系统链接：** 内容操作授权解析后的目标；移除和重命名授权并操作链接本身。递归 `rmdir` 拒绝末级符号链接。Windows rename 使用 async 0.22.5，保留链接目标。[文件系统授权](../introduction/application-api.md#扩展与能力)
- **桌面 shell：** macOS 和 Linux 与 Windows 一样支持打开和选中文件。等待外部工具时会让出执行权，并支持取消。Linux 需要 `gio`；选中文件还需要 `dbus-send` 和兼容的文件管理器。[运行环境](../introduction/installation.md)
- **屏幕监听：** Linux 只在注册成功后报告 `Watching`，启动竞态不再丢失立即到达的事件或启动错误。
- **更新 manifest：** 从原始整数文本精确解析整个正 `Int64` 范围内的 `size`。`size` 和 `schema_version` 拒绝小数及指数记法，包括可能经浮点解析舍入为整数的值。[更新下载契约](../introduction/application-api.md#应用更新)

**升级要求**

按[运行环境](../introduction/installation.md)使用 MoonBit 的 `latest` 工具链通道。将 CLI 和应用的 `proton_*` 依赖统一更新到 0.5.1，完成上述迁移，再执行 `proton_cli cef setup` 并重新打包应用。Async 更新到 0.22.5，Rabbita 保持 0.16.4，Warren 保持 0.4.5。CEF 版本不变，但 helper 与 Proton 版本对应。安装 CLI 不会改写已有应用。

[完整改动](https://github.com/moonbit-community/proton/compare/824db7a1acf20fa54d111145c321e464e30dbbae...18915e6b3c852b760dee6550f066f46d95a1248d)

## 0.5.0

0.5.0 将应用配置改为 MoonBit 瀑布语法，以作用域 setup 与 cleanup 替代成对生命周期钩子，并将浏览器决策放到所属页面或会话上。应用更新协议也有变化，现有应用需要迁移源码。

**不兼容变更与迁移**

| 范围 | 0.4.0 | 0.5.0 |
| --- | --- | --- |
| App 配置 | 配置方法返回 `App`，使用 `.` 链式调用 | 方法返回 `Unit`，配置改用 `..config(...)`、`..commands(...)` 等；查询和 `run()` 保留单点 |
| 应用生命周期 | `app_lifecycle(on_start=..., on_shutdown=...)` | `setup(context => { ... })`；状态保存在闭包中，立即用 `context.add_cleanup(...)` 注册清理 |
| 窗口生命周期 | `window_lifecycle(on_ready=..., on_close=...)` | `setup_window(context => { ... })` 与 `WindowContext.add_cleanup`；重新打开窗口会建立新作用域 |
| 退出决策 | `on_before_quit`、`on_will_quit` | `set_before_quit_handler`、`set_will_quit_handler`；每个入口替换此前的处理器 |
| 会话决策 | `on_certificate_error`、`on_media_permission_request`、`on_download_request` | `set_certificate_error_handler`、`set_media_permission_handler`、`set_download_handler` |
| 通用权限回调 | `on_permission_request`、`PermissionRequest` | 移除，改用专用证书及媒体权限处理器 |
| 窗口关闭 | `App.on_window_close_request` | 各窗口的 `WindowConfig.close_handler` |
| 导航／新窗口 | 应用级 `on_navigation_request`、`on_new_window_request` | `WindowConfig` 或 `ViewConfig` 上的 `WebContentsPolicy`；子视图不继承父窗口策略 |
| 创建及最终退出通知 | 异步 `on_session_created`、`on_window_created`、`on_web_contents_created`、`on_quit` | 同步且不抛错；需要等待的工作使用 setup／cleanup |
| 句柄表示 | 公开的函数值实现字段 | 运行时创建的句柄与公开方法；移除字段分发及自行构造句柄的代码 |
| 应用更新 | 独立 `revision`、schema 2、`rsa-sha256:<modulus>:<exponent>` 公钥 | 应用 `version`、schema 3、标准 `PUBLIC KEY` 或 `RSA PUBLIC KEY` PEM 文本 |

导航决策现在是**同步**的，不能挂起或抛错。它直接允许或拒绝原主 frame 导航，包括首次加载、跨域请求和被拦截的 `blob:` 导航；不再通过取消后重放实现 Allow。需要异步确认的应用主动导航，应先等待用户确认，再调用 `load_url`。新窗口、关闭、退出、证书、媒体和下载决策仍为异步。[回调契约](../introduction/application-api.md#宿主回调契约)

`on_*` 追加观察者，`set_*_handler` 替换决策处理器。异步观察者不阻止原操作继续，可以相互重叠；setup 会被等待，错误可使启动失败。通过 `add_cleanup` 注册的清理在作用域任务结束后逆序执行并受到取消保护，初始化部分失败或取消时也执行。只需要初始化或清理时，不必再传入另一端的空回调。[生命周期](../introduction/application-api.md#应用生命周期)

匹配 `LifecycleHookError` 时，应用清理改为 `ApplicationShutdown(detail)`，不再带钩子索引；窗口清理改为 `WindowClose(window, detail)`，携带窗口声明 ID。

更新发布流程移除 `--updater-revision` 和 `updater public-key` 命令；`package --version` 或 `package.version` 是唯一的应用发布版本，同版本重新构建不构成更新。通过 OpenSSL 导出标准 PEM 公钥。已有客户端继续保留 schema 2 端点，迁移到 schema 3 需要手动升级或专门准备的过渡版本。[更新打包](../command-line-interface/packaging.md#更新产物与元数据)

未使用的 `proton/catalog` 包已移除。扩展操作仍从命令绑定产生，应用继续通过 capability 注册并授权。

**新增与修复**

- **Dock 与徽章：** `ApplicationContext` 新增数字徽章及 macOS Dock 文本／提醒 API。不支持徽章的平台返回 `false`；macOS 专属 Dock 操作在其它平台抛出 `UnsupportedPlatform`。[平台约定](../introduction/application-api.md#进程控制与指标)
- **创建通知：** 创建观察者中添加的视图只通知一次，已被此前观察者移除的视图不再收到创建通知。窗口开始清理后拒绝迟到导航，不再用正在释放的资源执行应用策略。
- **Windows 输入焦点：** 原生窗口框架激活及 `focus()` 会恢复浏览器键盘／输入法焦点，包括此前聚焦的可见子视图。修复了一条焦点丢失路径，应用仍应在 Windows 验证受影响的输入法场景。
- **更新下载：** macOS 选用应用 ZIP，Windows 选用 NSIS 安装器，Linux 选用 AppImage。HTTPS 下载支持相对重定向，最多五跳；产物流式写盘，使用已认证的 `Int64` 大小，1 MiB 元数据上限不限制应用产物。响应头与接收字节校验拒绝大小不匹配。[下载约定](../introduction/application-api.md#应用更新)
- **CDP 自动化：** 可选的原生 `proton_cdp` 包使用同一发布版本。默认连接已有调试端点，只有显式调用启动操作时才会启动 Chrome 窗口。[CDP 参考](../command-line-interface/debugging.md#原生-cdp-自动化)

**升级要求**

使用支持显式 `Int32`／`UInt32` 的 stable MoonBit 工具链（2026-10-12 或更新版本）。isomorphic 模板使用 Warren 0.4.5，Rabbita 仍为 0.16.4，async 仍为 0.22.4。CEF 版本不变，但 helper 与 Proton 发布版本对应。

将 CLI 和应用的 `proton_*` 依赖升级至 0.5.0，执行 `proton_cli cef setup`，迁移上述调用后重新打包，使 helper 和应用版本元数据匹配。安装 CLI 不会重写现有源码或更新端点。[完整源码变更](https://github.com/moonbit-community/proton/compare/ae8f69ed637afda91b79b7c06f95ffb4d6a954d2...6c7c6810b492ffdc57b0908fc926d67db6656eef)

## 0.4.0

0.4.0 统一了窗口与浏览器 API，让应用与 CLI 共用类型化配置，并将更新安装纳入应用退出流程。本版包含不兼容的 API 变更。

**破坏性 API 变更与迁移**

| 范围 | 0.3.4 | 0.4.0 |
| --- | --- | --- |
| 窗口配置 | 主窗口独立 setter，附加窗口使用 `add_window(id, title, entry, ...)` | `App(config)`、`main_window(config)`、`add_window(id, config, ...)` 共用 `WindowConfig` |
| 初始子视图 | `App.with_view(...)` | 主窗口和附加窗口都使用 `WindowConfig.views` |
| 浏览器操作 | `window.browser()`，以及 `ViewHandle` 上的页面方法 | `window.web_contents()` 和 `view.web_contents()`，统一返回 `WebContentsHandle` |
| 浏览器事件 | `BrowserEvent`、`ViewEvent` 及独立订阅 | `WebContentsEvent` 与 `on_web_contents_event`；用 `window_id()` 和可选的 `view_id()` 区分实例 |
| 会话 | 依附浏览器的句柄、`SessionHandle.window_id()`、`WindowSessionError` | 应用级句柄、`context.session()`、`SessionError`；移除 `window_id()` |
| PDF | 请求编号与 `PdfPrinted` / `PdfPrintResult` | 异步 `web_contents.print_to_pdf(path, options?) -> Unit` |
| 配置 | `app.load_config()`、`ProjectConfig`、`AppMetadataError` | `app.config(@proton.load_config())`、类型化 `AppConfig`、`AppConfigError` |
| 更新 | `update.install(); update.restart()` | `update.download(); context.quit_and_install()` |

- **窗口配置：** 将 `title`、`size`、`theme`、`titlebar_style`、`traffic_light_position` 和 `entry_*` builder 设置迁入 `WindowConfig`。保留 `html`、`url`、`file`、`asset` 快捷入口；运行中的原生窗口控制仍属于 `WindowHandle`。窗口注册复制初始 views 数组，附加窗口重新打开时重新创建声明的子视图。[#417](https://github.com/moonbit-community/proton/pull/417)
- **Web contents：** `WebContentsHandle` 从需要拆分的枚举变为统一的不透明句柄，导航、下载、权限回调也接收该句柄。窗口缩放和子页面操作迁移到它；布局、显示、层级和移除仍属于视图。子页面获得打印、下载和会话访问，但不因此获得应用命令桥接。请求完成结果保持与来源页面对应，macOS 主页面标题更新也能正确送达。[#418](https://github.com/moonbit-community/proton/pull/418)
- **会话生命周期：** Cookie、缓存、认证、证书例外和连接操作统一使用应用的共享 request context。窗口创建前、页面关闭后以及 `KeepRunning` 无窗口期间均可使用。并发 Cookie 查询相互独立；运行时退出唤醒待完成查询，并使保留句柄失效。错误处理改为 `SessionError`。仍是共享 profile，不是每窗口独立会话。[#419](https://github.com/moonbit-community/proton/pull/419)
- **PDF 完成语义：** 在异步上下文直接调用 `print_to_pdf` 并处理结果，删除请求编号和事件关联。页面关闭、renderer 终止或应用关闭都会结束待完成等待。取消只停止等待，不取消原生打印任务，因此仍可能生成文件。[#433](https://github.com/moonbit-community/proton/pull/433)
- **类型化配置：** `@proton.load_config()` 一次读取完整配置，可直接访问 `config.frontend.dev_url` 等字段。`App.config(config)` 保存独立快照，`name()` / `version()` 不再重新打开文件。CLI 将开发覆盖参数写入启动快照。打包后的 `proton-package.json` 改为包含嵌套 `package` 的完整配置结构，需要一起重建应用与打包元数据。Rabbita 及模板默认值升级到 0.16.4，移除已弃用的 moonback 依赖。[#435](https://github.com/moonbit-community/proton/pull/435)
- **更新生命周期：** 下载只校验并保留产物，不替换文件；安装须经过可取消的退出流程，并在运行时清理成功后执行。拒绝退出保留下载，普通退出丢弃下载，强制退出覆盖安装请求。成功交接后终止旧进程，包括退出码为零的情况。`quit_and_install()` 返回表示请求已接受，不表示新版已启动。扩展响应改名为 `UpdateDownloaded`，移除旧 `changed` 字段。[#436](https://github.com/moonbit-community/proton/pull/436)

**修复**

- 启动或运行期间取消执行 `App.run()` 的任务，现在也会清理原生窗口、浏览器和 helper；取消仍向调用方传播。[#414](https://github.com/moonbit-community/proton/pull/414)
- Linux 和 macOS 打包正确复制路径以 `-` 开头的文件及目录，并保留执行权限。[#415](https://github.com/moonbit-community/proton/pull/415)
- 更新安装在替换应用文件期间保留单实例独占权。Windows 自动更新等待原进程退出，不再强制终止；macOS 新版本更换可执行文件名后仍可重启。配置更新渠道的 macOS/Linux 应用会拒绝被替换的旧可执行文件延迟启动。[#436](https://github.com/moonbit-community/proton/pull/436)

**升级说明**

CLI 与应用的 `proton_*` 依赖应使用相同版本，再执行 `proton_cli cef setup` 安装匹配的 helper。安装新版 CLI 不会迁移现有应用代码。重新打包应用以生成新版配置格式。

Rabbita 升级至 0.16.4；Warren 仍为 0.3.3，async 仍为 0.22.4，CEF 版本不变。参见[应用 API](../introduction/application-api.md)、[配置参考](../configuration/project.md)和[完整变更](https://github.com/moonbit-community/proton/compare/51a88c4c0892ff9628e5795fc598d05262e96daa...bdb169302952db553deda6de015887c7a6a19831)。

## 0.3.4 — 2026-09-28

- **生命周期：**新增应用退出拦截、强制退出、应用级窗口／浏览器／会话事件及焦点和显隐控制。修复 will_quit 中强制退出、exit(0)、子视图 renderer 通知、页面恢复与关闭记录回收。
- **通信：**保留命令错误码，区分业务命令失败与运行时失败，移除全局待响应请求数量上限。扩展操作清单从绑定生成。
- **浏览器 API：**增加导航历史和插入 CSS 控制；任务指标明确区分 CEF task 和进程。
- **平台与打包：**修复 Windows 桌面媒体授权及子视图布局、macOS 查询的 autorelease pool 和错误弹窗布局；完善打包锁，提供显式最低 macOS 版本元数据，保留 AppImage 中 helper 的可执行权限。
- **CLI：**new 不再对已经显式提供的选项重复询问。async 升级至 0.22.4。

**应用升级**

CLI 和应用的 proton_* 模块统一使用 0.3.4，并执行 `proton_cli cef setup` 安装匹配的 helper。重新安装 CLI 不会重写已有项目。

曾短暂引入的 app_metrics 改为 `task_metrics` 与 `AppTaskMetric`：任务身份不是进程身份，不同任务的 `process_cpu_percent` / `process_memory_bytes` 可能重复，不能直接相加作为应用总用量。参见 [PR #412](https://github.com/moonbit-community/proton/pull/412)。[PR #408](https://github.com/moonbit-community/proton/pull/408)删除了未使用的旧命令配置 API；应用命令继续通过绑定注册。

## 0.3.3 — 2026-09-21

- **视图生命周期：**移除或显式关闭子视图后，保留投递最终关闭事件所需的实例身份。覆盖浏览器创建前关闭、替换后的旧事件等情况。[PR #378](https://github.com/moonbit-community/proton/pull/378)
- **依赖更新：**async 0.22.1、x 0.5.5、lexer/parser/moon_config 0.4.0、Rabbita 0.16.2、Warren 0.3.3。模板默认版本同步更新，取消处理与受保护的清理适配 async 新语义。[PR #379](https://github.com/moonbit-community/proton/pull/379)

**应用升级**

应用的 `proton_*` 依赖和 CLI 统一使用 0.3.3。已有项目保留原配置和源码，安装新版 CLI 不会重写它们。使用 isomorphic 前端时安装 Warren 0.3.3，构建前运行 `proton_cli cef setup` 安装匹配的 helper。

直接使用 async 的应用需要关注 0.22 的取消语义：取消不再作为普通错误被捕获。等待已取消任务的 `wait()` 可以报告 `TaskCancelled`；子进程关闭则可以在完成回收后返回退出结果。

### 更早的发布历史

更早的变更见 [0.3.2 变更](https://github.com/moonbit-community/proton/pull/377)和[仓库历史](https://github.com/moonbit-community/proton/commits/main/)。
