# 管理窗口

[English](../../tutorial/windows.html)

应用构建器在启动前描述窗口，`WindowHandle` 则控制已经运行的窗口。本章使用 minimal 项目及其已有包导入。

## 创建第二个窗口

将 **`app/main.mbt`** 替换为：

```moonbit
///|
async fn main {
  @proton.html("Main", "<h1>Main window</h1>", width=900, height=700)
  .load_config()
  .add_window(
    "help",
    "Help",
    @proton.AppEntry::Html("<h1>Help</h1><p>Close this window to return.</p>"),
    width=480,
    height=320,
  )
  .window_lifecycle(
    on_ready=context => {
      let id = context.handle().id()
      println("Ready: " + id)
      id
    },
    on_close=id => println("Closed: " + id),
  )
  .run_or_abort()
}
```

执行 `proton_cli dev`，应同时打开 **Main** 和 **Help**。终端在每个窗口就绪和关闭时输出其 ID。关闭 Help 后 Main 仍然运行，关闭最后一个窗口则退出应用。

主窗口 ID 是 `main`，辅助窗口 ID 必须非空、唯一，且不能使用 `main`。ID 在代码中标识窗口，标题则用于显示。

## 按需打开窗口

`add_window` 默认在启动时打开声明的窗口。设置 `open_on_start=false` 后，只声明窗口而不立即打开；之后从应用或窗口上下文调用 `context.windows().open("help")`。

例如，在上面的 Help 声明中加入 `open_on_start=false`，然后在 `.run_or_abort()` 之前添加以下构建器调用，即可从应用启动钩子打开它：

```moonbit
.app_lifecycle(
  on_start=context => { ignore(context.windows().open("help")) },
  on_shutdown=_ => (),
)
```

后续用户操作也可以通过保留的应用上下文调用相同的窗口管理器操作。第二个窗口不需要第二套 Proton 运行时。

## 使用与释放句柄

`on_ready` 中的 `context.handle()` 返回当前 `WindowHandle`，可用于 `focus()`、`hide()`、`show()`、`close()` 等操作。浏览器操作通过 `handle.browser()` 获取。

生命周期回调的返回值会成为对应 `on_close` 的参数。示例返回窗口 ID，Todo 模板则用这个 ID 移除保存的事件目标。将窗口所属状态放在这一生命周期内管理，关闭后停止使用句柄。

## 决定应用何时退出

默认策略是在最后一个窗口关闭后退出。托盘和后台应用可以加入：

```moonbit
.last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
```

此时关闭全部窗口不会结束进程。在实际应用采用该策略前，应先提供明确的退出操作。

需要异步决定是否允许关闭时，使用 `on_window_close_request`，返回 `WindowCloseDecision::Allow` 继续关闭，返回 `Deny` 保持窗口打开。确认对话框或未保存文档检查应放在这里，`on_close` 则用于关闭后的清理。

## 平台相关的窗口行为

原生窗口装饰和可用控制项因平台而异。依赖平台专属方法前，请查询[窗口 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/)。使用叠加标题栏时，需要一起处理前端标题栏布局与原生配置。

辅助页面也是独立的 capability 目标，只应授予其所需的宿主操作，见[原生能力](capabilities.md)。
