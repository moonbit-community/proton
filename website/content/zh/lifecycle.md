# 应用生命周期

[English](../lifecycle.html)

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

钩子签名与错误变体见[应用 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.0/)。
