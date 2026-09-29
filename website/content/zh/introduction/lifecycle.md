# 应用生命周期

`App` 描述启动前的应用配置，通过 Proton 根包创建，在 MoonBit 异步运行时中执行。Proton 在初始化期间接入原生事件循环，应用代码不负责安装或轮询另一个 UI 循环。

## 入口来源

| 构造函数 | 入口 |
| --- | --- |
| `html(title, html, ...)` | 内联 HTML 文档 |
| `url(title, url, ...)` | URL |
| `file(title, path, ...)` | 本地 HTML 文件 |
| `asset(title, path, ...)` | 托管应用资源入口 |

各函数返回 `App` 构建器，共同选项包括宽度、高度、调试模式和是否允许调整大小。`entry_html`、`entry_url`、`entry_file`、`entry_asset` 可修改已有构建器的入口。

## 应用身份

`load_config()` 读取托管应用元数据，包括必需的 identifier。非托管应用可以显式调用 `identifier(...)`。identifier 是稳定的应用身份，与窗口标题、产品显示名称和应用版本不同。

`app_path()`、`resource_dir()` 和 `is_packaged()` 描述执行环境。开发路径与打包资源的位置不同，前端 URL 也不是后端文件系统路径。

## 钩子与状态所有权

| 钩子 | 含义 |
| --- | --- |
| `app_lifecycle(on_start, on_shutdown)` | 应用级状态；启动钩子的返回值传给退出钩子 |
| `window_lifecycle(on_ready, on_close)` | 窗口级状态；ready 返回值传给 close |
| `on_window_close_request` | 窗口关闭前的异步允许／拒绝决策 |

应用和窗口上下文提供任务组与窗口管理器。窗口上下文还提供窗口句柄和事件发送器。窗口状态不应比其引用的资源存活更久。

## 执行与退出

`run()` 是异步方法，可抛出 `AppRunError`。`run_or_abort()` 报告失败并中止，而不是向调用方返回类型化错误。默认的 `LastWindowClosedPolicy::Quit` 在最后窗口关闭后发起应用退出；`KeepRunning` 保留进程。`ApplicationContext.quit()` 请求应用退出。

窗口消失不等于应用清理完成。浏览器和子视图必须完成销毁，运行时才能正常退出。强制结束进程不等价于成功执行生命周期。

钩子签名与错误变体见[应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。

## 启动顺序

启动先校验配置、解析身份与路径、初始化日志，并在启用单实例时获取锁。次实例成功转发激活请求后返回，不会创建自己的应用运行时。

主实例先建立会话，再执行应用启动钩子。启动钩子成功建立应用状态后，Proton 打开尚未由启动钩子打开的启动窗口，等待所需 bridge 初始化，再通过 ready 钩子激活初始窗口。初始激活成功后应用才进入 ready；声明窗口或收到原生创建通知都不代表已经 ready。

启动钩子可以等待 `context.windows().open(id)`。已提交的退出会停止启动；被拒绝的退出请求会保留应用运行，提出 quit 请求本身不等于已提交退出。

## 退出决策与强制退出

| 操作 | 契约 |
| --- | --- |
| `context.quit(exit_code=0)` | 请求正常退出，可以被取消 |
| `context.exit(exit_code=0)` | 强制退出并终止进程，包括退出码为零时 |
| `handle.close()` | 请求关闭该窗口，受其关闭拦截器约束 |

正常退出依次执行 on_before_quit、各窗口的关闭决策、窗口关闭后的 on_will_quit。`ApplicationQuitDecision::Prevent` 取消退出；窗口拒绝关闭也会取消整个退出请求。取消不会重新创建已经关闭的窗口。on_quit 在运行时清理前观察最终退出码，不能再否决退出。

强制退出跳过可取消的决策，包括已经等待中的决策，但仍执行最终退出通知与运行时清理，因此不同于从外部杀死进程。已经安排的 relaunch 在清理后、进程终止前启动。

普通退出以零状态成功完成时，`App.run()` 返回；非零状态的普通退出会以该状态终止进程。强制退出即使状态为零也会终止。必需的收尾不能只写在 run() 后面。

## 任务与清理所有权

应用任务放入应用 task group，窗口任务放入窗口 task group。退出时相应作用域取消并等待收尾；仅仅持有窗口句柄，不会使作用域之外的后台工作自动拥有正确的生命周期。

每个成功返回状态的生命周期钩子会安装配对清理钩子。若钩子在返回前失败，就没有可传给配对清理的状态，但此前成功建立的作用域仍会清理。清理钩子受取消保护；清理失败可以与原始错误一起出现在 AppRunError 中，而不会简单覆盖原始诊断。

ready／close 钩子管理窗口状态；创建通知和浏览器事件用于观察。renderer 导航或崩溃时，原生窗口仍可能存活，页面任务与订阅还必须遵守[命令](commands-events.md)和[事件](events.md)说明的页面有效期。
