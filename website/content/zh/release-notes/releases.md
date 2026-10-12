# Release Notes

## 0.4.0（待发布）

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
