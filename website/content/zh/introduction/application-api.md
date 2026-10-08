# 应用 API 参考

根包 moonbit-community/proton 是公开应用入口。运行前使用 App 构建器；运行中使用上下文和句柄。CLI 项目元数据不能代替运行时配置。

| 领域 | 所属对象／入口 | 参考 |
| --- | --- | --- |
| 启动、ready、退出与任务清理 | App、ApplicationContext、生命周期钩子 | [生命周期](#应用生命周期) |
| 窗口声明、实例与子浏览器 | App、WindowManager、WindowHandle、ViewHandle | [窗口](#窗口与浏览器视图) |
| 请求／响应通信 | 契约、注册器、客户端 | [命令](#命令) |
| 前端通知与订阅有效期 | emitter、客户端订阅 | [事件](#事件) |
| 宿主操作与 renderer 授权 | App.capability、扩展范围 | [能力](#扩展与能力) |
| Cookie、浏览器存储与代理 | SessionHandle、启动构建器 | [浏览器会话](#浏览器会话) |
| 签名应用更新 | App.update_channel、PendingUpdate | [自动更新](#应用更新) |
| 进程所有权与激活 | 单实例构建器、上下文方法 | [进程控制](#进程控制与指标) |
| 菜单、语言与后台驻留 | 窗口／应用配置 | [精选示例](../examples/01_run.md) |
| 路径、文件与构建元数据 | 项目配置、应用路径 | [项目结构](project-structure.md)、[Configuration](../configuration/project.md) |

完整方法、类型化错误和默认参数见[版本化 API 索引](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。本书说明对象关系与行为约定，不复制每一条签名。参考页中的短片段用于解释 API，不要求读者先修改某个教程项目。

## API 参考

- [应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)
- [扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)
- [类型化契约](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.4/)
- [前端客户端](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.4/)
- [Rabbita 集成](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/)

生成的 API 文档提供完整签名；本站参考文档说明行为约定和 API 之间的关系。

## 应用生命周期

`App` 描述启动前的应用配置，通过 Proton 根包创建，在 MoonBit 异步运行时中执行。Proton 在初始化期间接入原生事件循环，应用代码不负责安装或轮询另一个 UI 循环。

**入口来源**

| 构造函数 | 入口 |
| --- | --- |
| `html(title, html, ...)` | 内联 HTML 文档 |
| `url(title, url, ...)` | URL |
| `file(title, path, ...)` | 本地 HTML 文件 |
| `asset(title, path, ...)` | 托管应用资源入口 |

各函数返回 `App` 构建器，共同选项包括宽度、高度、调试模式和是否允许调整大小。`entry_html`、`entry_url`、`entry_file`、`entry_asset` 可修改已有构建器的入口。

**应用身份**

`load_config()` 读取托管应用元数据，包括必需的 identifier。非托管应用可以显式调用 `identifier(...)`。identifier 是稳定的应用身份，与窗口标题、产品显示名称和应用版本不同。

`app_path()`、`resource_dir()` 和 `is_packaged()` 描述执行环境。开发路径与打包资源的位置不同，前端 URL 也不是后端文件系统路径。

**钩子与状态所有权**

| 钩子 | 含义 |
| --- | --- |
| `app_lifecycle(on_start, on_shutdown)` | 应用级状态；启动钩子的返回值传给退出钩子 |
| `window_lifecycle(on_ready, on_close)` | 窗口级状态；ready 返回值传给 close |
| `on_window_close_request` | 窗口关闭前的异步允许／拒绝决策 |

应用和窗口上下文提供任务组与窗口管理器。窗口上下文还提供窗口句柄和事件发送器。窗口状态不应比其引用的资源存活更久。

**执行与退出**

`run()` 是异步方法，可抛出 `AppRunError`。`run_or_abort()` 报告失败并中止，而不是向调用方返回类型化错误。默认的 `LastWindowClosedPolicy::Quit` 在最后窗口关闭后发起应用退出；`KeepRunning` 保留进程。`ApplicationContext.quit()` 请求应用退出。

窗口消失不等于应用清理完成。浏览器和子视图必须完成销毁，运行时才能正常退出。强制结束进程不等价于成功执行生命周期。

钩子签名与错误变体见[应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。

**启动顺序**

启动先校验配置、解析身份与路径、初始化日志，并在启用单实例时获取锁。次实例成功转发激活请求后返回，不会创建自己的应用运行时。

主实例先建立会话，再执行应用启动钩子。启动钩子成功建立应用状态后，Proton 打开尚未由启动钩子打开的启动窗口，等待所需 bridge 初始化，再通过 ready 钩子激活初始窗口。初始激活成功后应用才进入 ready；声明窗口或收到原生创建通知都不代表已经 ready。

启动钩子可以等待 `context.windows().open(id)`。已提交的退出会停止启动；被拒绝的退出请求会保留应用运行，提出 quit 请求本身不等于已提交退出。

**退出决策与强制退出**

| 操作 | 契约 |
| --- | --- |
| `context.quit(exit_code=0)` | 请求正常退出，可以被取消 |
| `context.exit(exit_code=0)` | 强制退出并终止进程，包括退出码为零时 |
| `handle.close()` | 请求关闭该窗口，受其关闭拦截器约束 |

正常退出依次执行 on_before_quit、各窗口的关闭决策、窗口关闭后的 on_will_quit。`ApplicationQuitDecision::Prevent` 取消退出；窗口拒绝关闭也会取消整个退出请求。取消不会重新创建已经关闭的窗口。on_quit 在运行时清理前观察最终退出码，不能再否决退出。

强制退出跳过可取消的决策，包括已经等待中的决策，但仍执行最终退出通知与运行时清理，因此不同于从外部杀死进程。已经安排的 relaunch 在清理后、进程终止前启动。

普通退出以零状态成功完成时，`App.run()` 返回；非零状态的普通退出会以该状态终止进程。强制退出即使状态为零也会终止。必需的收尾不能只写在 run() 后面。

**任务与清理所有权**

应用任务放入应用 task group，窗口任务放入窗口 task group。退出时相应作用域取消并等待收尾；仅仅持有窗口句柄，不会使作用域之外的后台工作自动拥有正确的生命周期。

每个成功返回状态的生命周期钩子会安装配对清理钩子。若钩子在返回前失败，就没有可传给配对清理的状态，但此前成功建立的作用域仍会清理。清理钩子受取消保护；清理失败可以与原始错误一起出现在 AppRunError 中，而不会简单覆盖原始诊断。

ready／close 钩子管理窗口状态；创建通知和浏览器事件用于观察。renderer 导航或崩溃时，原生窗口仍可能存活，页面任务与订阅还必须遵守[命令](#命令)和[事件](#事件)说明的页面有效期。

## 命令

命令是跨渲染器与宿主边界的类型化请求／响应操作。载荷经过序列化；共享 MoonBit 类型不会共享内存，也不会让前端直接执行后端代码。

**契约与绑定**

| API | 约定 |
| --- | --- |
| `proton_contract.command[Request, Response](name)` | 声明类型化应用路由，不注册处理器 |
| `App.commands(register, targets?)` | 为指定渲染器目标安装应用命令绑定 |
| `CommandRegistrar.bind(command, handler)` | 绑定接收 `(CommandContext, Request)`、返回 `Response` 的异步处理器 |
| `proton_client.invoke(command, request)` | 前端异步调用，返回 `Response` 或抛出 `ClientFailure` |
| `proton_rabbita.invoke(...)` | 将成功与失败映射到 Rabbita 命令 |

后端要求 `Request` 实现 `FromJson`、`Response` 实现 `ToJson`；前端要求相反方向的转换。契约与注册错误不同于运行中请求的失败。应用路由名称必须合法且唯一；绑定和调用时都会验证描述符。

处理器上下文标识调用方，并提供 `emit_to_caller`。处理器可以等待后端异步工作。校验不通过等业务结果可以建模为响应类型，而不是通信失败。

**JavaScript 接口**

注入的 bridge 将应用方法暴露为 `window.__MoonBit__.app.<name>(request)`。调用返回 Promise，失败时 reject。应用路由使用 `app:`，扩展操作使用 `ext:`。普通浏览器页面没有注入的原生 bridge。

**载荷大小**

Proton 不对命令载荷设置固定的大小上限。载荷通过 JSON 序列化，仍受可用内存与底层传输约束。大消息会增加序列化、复制和解析开销。

**取消**

`proton_client.invoke_with_callbacks` 返回取消函数，用于取消响应观察并请求取消通信；迟到的响应会被忽略。异步 `invoke` 所在任务取消时，也会取消待完成请求。取消不保证撤销后端已经执行的操作。

**客户端错误**

| 变体 | 含义 |
| --- | --- |
| `BridgeUnavailable` | 原生 bridge 不存在 |
| `InvalidContract` | 命令或事件描述符不合法 |
| `RemoteFailure` | 后端拒绝，携带 code、message 和可选 detail |
| `TransportFailure` | 通信失败 |
| `ResponseDecode` | 响应无法解码为声明的类型 |
| `RequestCancelled` | 待完成请求被取消 |

命令向调用方返回结果，[事件](#事件)向观察者传递通知；两者都不意味着应用数据已经持久化。

完整签名见[客户端 API](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.4/)。逐步示例位于独立的[命令教程](../tutorial/commands-events.md)。

**命令错误码**

`RemoteFailure.code` 用于识别失败类型，无需解析错误消息：

| 错误码 | 含义 |
| --- | --- |
| `invalid_payload` | 请求不符合命令的输入类型 |
| `unknown_op` | 请求的操作未注册 |
| `handler_failed` | 命令处理函数抛出错误 |
| `host_closed` | 命令宿主已关闭 |
| `permission_denied` | 页面没有调用该操作的权限 |

根据错误码处理失败，并将未识别的错误码作为其它远程失败处理。完整后端诊断保留在应用日志中；开发模式下也会包含在 `detail` 中，`message` 始终是面向调用方的说明。预期业务结果应放在命令的响应类型中。

**请求作用域与页面失效**

每个获准执行的请求有自己的命令作用域，等待的工作、子任务和延迟清理都属于该请求。处理器或作用域内清理失败属于请求失败（handler_failed），不表示应终止应用。真正的运行时基础设施失败仍是应用级错误。

导航、renderer 终止或 bridge 失败会使旧页面的待响应请求失效。一次 bridge 尝试失败后，该失败页面不能继续发起新的应用命令，直到建立新的有效尝试。正常初始化期间允许请求，不要求所有请求都等到 ready，以免阻断初始化工作。

调用方取消及页面失效会停止等待并请求取消未完成工作，都不会回滚已经执行的业务副作用。重试不能重复执行的操作，应使用业务操作标识或事务。消息成功提交也不能被当作业务执行成功。

0.3.4 没有固定的全局并发请求准入上限。应用仍应根据资源和顺序要求限制昂贵工作；bridge 不会将彼此独立的业务操作自动串行为事务。

## 事件

事件是从宿主发往渲染器的类型化通知，没有响应值。`proton_contract.event[Payload](name)` 仅声明描述符，不安装监听器，也不保留历史通知。

**发送目标**

| API | 目标与有效期 |
| --- | --- |
| `CommandContext.emit_to_caller(event, payload)` | 发起当前命令的页面 |
| `WindowContext.events()` | 获取窗口事件发送器 |
| `WindowEventEmitter.emit(event, payload)` | 关联窗口仍存活时向其发送 |

宿主载荷要求实现 `ToJson`。窗口发送器的有效期受窗口生命周期约束；保存在应用状态中的发送器应在窗口关闭时移除。发送事件不意味着向全部窗口广播。

**订阅**

`proton_client.subscribe(event, listener, failure)` 通过 `FromJson` 解码载荷，返回 `Subscription`。`Subscription.close()` 释放监听器。订阅建立可能抛出 `ClientFailure`；事件解码失败通过 failure 回调报告 `EventDecode`。

`proton_rabbita.subscribe` 将订阅所有权接入 Rabbita，选项包括订阅 key、重试次数、ready 命令和 client 覆盖。完整签名见 [Rabbita API](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/)。

JavaScript 接口为 `window.__MoonBit__.app.on(name, callback)`。回调接收包含 `payload` 的事件对象；注册返回取消订阅函数。

**传递语义**

- 订阅之前错过的通知不会重放。
- 命令响应与事件是独立传递，二者的相对顺序不是应用同步约定。
- 释放监听器后停止观察；事件不是持久队列或确认协议。
- 状态变化通知可以使前端查询失效；权威快照通过命令获取。

[事件教程](../tutorial/events.md)演示订阅与清理；[Todo 教程](../tutorial/isomorphic.md)演示通知失效后重新查询快照。

**订阅有效期与状态同步**

订阅属于当前 renderer 文档或 UI 组件，所属对象销毁时应关闭订阅。重新加载会创建新文档，需要重新订阅；原生窗口继续存在不代表 JavaScript 监听器跨 reload 保留。

同步状态时，先订阅再读取初始快照，用事件使快照失效，并忽略已经被新查询替代的响应。先订阅消除了初次读取前的监听空档，但不会让两条独立消息成为原子事务。需要识别旧快照或遗漏变更时，应在业务数据中加入 revision。

on_window_created、on_render_process_gone 等应用生命周期通知是宿主回调，不是 proton_contract 前端事件。它们注册在 App 构建器上；前端也需要相关信息时，再通过命令或显式事件传递。

## 窗口与浏览器视图

窗口声明属于 `App`，运行中的窗口操作属于 `WindowHandle`。浏览器导航和开发者工具属于 `BrowserHandle`，通过 `WindowHandle.browser()` 获取。

**标识与声明**

主窗口 ID 为 `main`。`App.add_window(id, title, entry, ...)` 声明附加窗口，其 ID 必须非空、唯一，且不能为 `main`。标题是显示文本，不是窗口标识。

附加窗口默认在启动时打开。`open_on_start=false` 将打开推迟到 `WindowManager.open(id)`。`ApplicationContext.windows()` 和 `WindowContext.windows()` 提供窗口管理器。所有窗口属于同一个应用运行时。

**运行时操作**

| 领域 | `WindowHandle` 操作 |
| --- | --- |
| 显示与焦点 | `show`、`hide`、`focus`、`is_visible`、`is_focused` |
| 几何 | `bounds`、`set_bounds`、`position`、`set_position`、`content_size`、`set_content_size` |
| 窗口状态 | `minimize`、`maximize`、`restore`、`set_fullscreen` |
| 外观 | `set_theme`、`set_background_color`、`set_title`、`set_menu` |
| 生命周期 | `close` |

原生操作可能抛出 `WindowSessionError`。句柄不是永久有效的：窗口关闭时，应释放窗口所属状态以及保留的事件目标。隐藏的窗口仍然存活。

**关闭语义**

`App.on_window_close_request` 注册异步回调；回调接收窗口句柄，返回 `WindowCloseDecision::Allow` 或 `Deny`。`window_lifecycle.on_close` 是关闭后的清理钩子，不能否决关闭。最后窗口关闭策略默认为 `Quit`；`KeepRunning` 让应用在无窗口时继续运行，需要应用提供显式退出入口。参见[应用生命周期](#应用生命周期)。

**子浏览器视图**

`App.with_view` 在主窗口声明视图；`WindowHandle.add_view` 动态创建视图并返回 `ViewHandle`。视图是窗口内部承载的子浏览器，不是第二个顶层窗口。其边界以左上角为原点，显示状态和 z-order 独立于主页面。`remove_view` 移除子视图。关闭父窗口也必须完成子浏览器销毁。

**平台行为**

`WindowThemePreference` 控制窗口主题，`system_appearance()` 返回系统外观，二者是不同概念。标题栏样式和原生控件因平台而异。红绿灯位置设置适用于 macOS；使用叠加标题栏时，前端布局需要考虑原生控件占用的空间。

完整签名和选项见[窗口 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。可运行练习位于独立的[多窗口教程](../tutorial/windows.md)。

**打开操作与实例身份**

`WindowManager.open(id)` 是异步操作，返回已激活的 WindowHandle。id 选择窗口声明，不是以后每次原生实例的永久身份。关闭并重新打开后，应通过 open 或 find 获取新句柄，旧句柄不会重新有效。

激活提交前取消调用，会丢弃排队的打开操作，或关闭该操作已经创建的实例。激活成功提交后，窗口属于应用，随后取消调用方不会把它关闭。未知声明和无效窗口状态产生窗口会话错误；任务取消遵循 async 的取消语义。

hide() 保留窗口实例、浏览器和相关任务。close() 发起销毁流程且可能被拒绝，不能把关闭请求当作清理完成。窗口状态应由生命周期清理释放，而不是刚请求关闭就释放。

**浏览器与子视图边界**

主页面通过 WindowHandle.browser() 操作，子页面通过 ViewHandle 操作。子视图导航或移除不会导航或关闭主页面。应用级创建和 renderer 终止回调以 WebContentsHandle 统一表示两者。

on_render_process_gone 同时覆盖主页面和子视图，无需额外订阅 on_view_event。renderer 终止会使页面工作失效，但不等于正常关闭窗口。应用根据终止详情决定重新加载还是展示恢复界面，并在导航后重新建立页面订阅。

视图坐标以父窗口内容区左上角为原点。固定声明不提供自动布局；布局变化时由应用更新边界。移除视图结束其浏览器生命周期，关闭父窗口也会销毁子视图。

## 扩展与能力

扩展注册可复用的宿主操作。渲染器能力安装扩展后端，并向指定渲染器目标授予权限范围。添加 `proton_ext` 模块依赖仅使代码可用，不安装处理器，也不授予访问权限。

**注册与目标**

`App.capability(capability, targets?)` 配置安装与访问范围。不指定 targets 时，授权作用于主入口。`RendererTarget.entry(window=...)` 和 `RendererTarget.bundled(window=...)` 选择命名窗口的入口或打包页面目标。窗口属于同一个应用，不代表其权限自动变为全局。

应用命令使用 `app:` 路由，扩展操作使用 `ext:<extension>/<operation>`。JavaScript 通过 `window.__MoonBit__.core.invokeOp(route, request)` 调用已安装操作，返回 Promise。

**文件系统权限范围**

`proton_ext/fs.capability` 接收 `PermissionRoot`，每项将一个宿主目录与允许的操作绑定。范围由后端配置，渲染器请求不能扩大它。

| 属性 | 行为 |
| --- | --- |
| 相对根路径或请求路径 | 相对于 `resource_dir()` 解析 |
| 超出授权根目录的路径 | 拒绝，包括符号链接逃逸 |
| 根目录授权中没有列出的操作 | 不被该授权允许 |
| 文本载荷 | UTF-8 |

文件系统操作包括 `read_file`、`write_file`、`mkdir`、`readdir`、`remove`、`rmdir`、`rename`、`realpath`、`exists`、`kind` 和 `size`。扩展内部将规范路径检查和操作串行执行。

**可用性与错误**

缺少能力声明时，路由不可用。扩展已安装时，仍可能因权限范围、参数、平台限制或操作系统错误拒绝请求。这些错误通过命令 bridge 报告；安装不意味着所有原生操作必然成功。

文件系统、对话框、剪贴板、shell、托盘等能力使用不同的范围类型，平台覆盖也不同。0.3.4 的通知扩展面向 macOS。框架支持的平台列表不等同于各能力的支持矩阵。

完整构建器及请求／响应类型见[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)。完整练习位于独立的[文件访问教程](../tutorial/capabilities.md)。

**平台差异与选择**

以下是 0.3.4 已实现能力的主要边界，不承诺缺少桌面服务时仍可用：

| 能力 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| 文件、路径、宿主 HTTP、子进程 | 支持 | 支持 | 支持 |
| 原生对话框、文本剪贴板 | 支持 | 支持 | 依赖桌面会话／GTK 等后端 |
| 系统通知扩展 | 支持 | 未实现 | 未实现 |
| 托盘 | 菜单及平台事件 | 点击、右击、双击和菜单 | 依赖 AppIndicator／Ayatana 与桌面会话 |
| 桌面来源与缩略图 | 显示器；缩略图需要屏幕录制权限 | 可见有标题窗口及 GDI 缩略图 | X11/RandR 显示器；缩略图为 null |

capability 授权与操作系统授权不同。声明屏幕或媒体能力不会自动获得系统隐私权限；系统拒绝、后端不可用与应用未授权应分别处理。托盘等提供 support 查询的能力应先检查支持情况，菜单事件也比各平台鼠标手势更可移植。

net 扩展在宿主执行 HTTP 请求，返回状态、响应头及 UTF-8 文本；它不等于浏览器 fetch，不共享浏览器 cookie jar，也不自动跟随重定向。二进制数据不是该文本响应接口的无损用途。process 扩展创建的进程属于扩展应用生命周期，wait 回收句柄，kill 后仍需 wait，应用退出会取消并回收剩余子进程。

完整扩展清单及各范围类型见[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)。访问某个 API 前分别确认：目标授权、操作系统授权、平台后端支持。

## 浏览器会话

浏览器会话保存 Cookie、缓存、认证状态和 Web storage，通过 window.browser().session() 获取句柄。虽然句柄来自一个浏览器，清理共享会话数据并不是仅对这个页面的私有操作。

**启动配置**

App.session_partition(name) 选择应用 sessionData 目录下的持久 profile。这是应用启动配置，不是每窗口独立的无痕开关；运行时中的窗口使用该配置的 profile。保持应用 identifier 和 partition 稳定才能跨启动保留数据。

App.proxy(server, bypass?) 配置 Chromium 启动级代理，运行中不能修改。它控制浏览器流量，不会自动配置宿主内每一个 MoonBit 网络库。

on_session_created 在应用启动钩子创建窗口前提供 partition 和解析后的数据路径。打包资源与浏览器 profile 是不同目录，不应将可写 profile 放入应用 bundle。

**操作**

| API | 效果 |
| --- | --- |
| get_cookies | 异步读取匹配的 Cookie，可选择 URL 及是否包括 HttpOnly |
| set_cookie | 以 URL、名称、值及可选 domain/path/安全属性设置 Cookie |
| delete_cookies、flush_cookies | 删除选定 Cookie，或将持久 Cookie 存储刷盘 |
| clear_cache、clear_storage_data | 清缓存或选定类型的 Web storage |
| clear_auth_cache | 清除 HTTP 认证缓存 |
| clear_certificate_exceptions | 清除证书例外状态 |
| close_all_connections | 关闭会话连接 |

所属浏览器或窗口不再可用时操作可能失败。Cookie 异步读取应在有效生命周期作用域内等待。清理浏览器存储不会删除应用自己管理的文件，也不等于完成业务登出；后端凭据和 UI 状态需单独处理。

完整属性及 StorageDataKind 变体见[API 参考](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。

## 应用更新

应用更新替换分发中的应用，不更新开发 CLI 或 Mooncakes 依赖。运行前通过 App.update_channel(endpoint, public_keys, check_on_launch?, freshness_days?) 配置。

**更新渠道与检查**

endpoint 必须是 HTTPS，至少配置一个受信任 RSA 公钥。默认开启自动检查，manifest 新鲜度默认为 30 天且必须为正数。公钥格式由 [updater public-key](../command-line-interface/commands.md#updater-public-key) 校验。

自动检查在启动成功后进行，失败写入日志而不使应用启动失败。显式检查使用 ApplicationContext.check_for_update()，处理结果与异常。NotConfigured 与 UpToDate 不同；应用结束后，保留的上下文不再拥有活动更新渠道。

PendingUpdate 表示 manifest 已通过信任、新鲜度和 revision 检查。它提供 version、revision、size 和可选 notes URL，此时尚未下载产物。

**安装与重启**

安装必须显式调用 PendingUpdate.install()。下载先写入私有暂存区域，通过大小、摘要和签名验证后才能使用。应检查 UpdateInstallOutcome，不能假设所有平台都已经完成文件替换。macOS 和 Linux 在 install 中应用替换；Windows 保留已验证的 NSIS 安装器，待 restart 使用。

PendingUpdate.restart() 请求启动替换后的应用，调用方随后应退出。请求成功只表示操作系统接受启动，不代表新进程已经 ready。检查更新或收到更新通知都不会隐式安装。

未保存数据的处理应与检查、下载分开，通过[退出生命周期](#应用生命周期)决定何时退出。旧的受管理更新产物在成功启动后清理；暂存新包不代表新应用已经启动成功。

**发布者责任**

应用 identifier 保持稳定，revision 单调递增。[CLI package](../command-line-interface/commands.md#package) 的更新元数据选项指定产物位置、发布时间和 revision。updater public-key 只格式化公钥，不生成密钥、签署更新 manifest 或托管服务器。系统签名／公证与更新器签名验证承担不同检查，配置其中一项不会自动配置另一项。

## 进程控制与指标

**单实例所有权**

App.single_instance() 按应用身份选择一个持有进程。后续实例转发 URL、文档或 reopen 激活，主实例事件循环接受后返回；接受不代表异步激活处理器已经完成。转发有五秒期限，失败不会终止主实例，也不会另起一个持有者。

ApplicationContext.has_single_instance_lock() 查询所有权，release_single_instance_lock() 在运行期间释放锁。释放不终止进程；应用应明确决定是否允许另一个进程成为持有者。激活处理需要同时考虑初次启动和后续转发。

**应用状态与窗口状态**

应用的 focus、hide/show、active/hidden 查询及 readiness 描述整个应用；窗口句柄控制一个窗口。隐藏窗口仍然存活，KeepRunning 应用也能在没有窗口时继续运行。后台应用必须提供明确的退出入口。

**任务指标**

ApplicationContext.task_metrics() 返回 Chromium task 的 AppTaskMetric 列表。renderer 和多个 worker 可以共享进程。task id 标识任务；多个条目的 process_cpu_percent 和 process_memory_bytes 可能完全相同，因为它们属于同一个进程。不能将各行相加作为进程或应用总用量。

采样间隔尚未完成时 CPU 为零，100% 表示一个核心满载；内存测量前为 -1，不是零字节。这些观测不赋予应用对进程的所有权，不应借此绕过 Proton 生命周期单独杀死 helper。
