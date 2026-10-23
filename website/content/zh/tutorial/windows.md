# 管理窗口

本教程在[最小应用](first-app.md)中增加辅助窗口，并控制窗口的显示和关闭行为。请从该项目开始，保留已有包导入，用下面的代码替换应用入口。

## 创建第二个窗口

将 **`app/main.mbt`** 替换为：

```moonbit
///|
async fn main {
  @proton.html("Main", "<h1>Main window</h1>", width=900, height=700)
  ..config(@proton.load_config())
  ..add_window(
    "help",
    @proton.WindowConfig(
      "Help",
      @proton.AppEntry::Html("<h1>Help</h1><p>Close this window to return.</p>"),
      width=480,
      height=320,
    ),
  )
  ..setup_window(context => {
    let id = context.handle().id()
    println("Ready: " + id)
    context.add_cleanup(() => println("Closed: " + id))
  })
  .run_or_abort()
}
```

执行 `proton_cli dev`，应同时打开 **Main** 和 **Help**。终端在每个窗口就绪和关闭时输出其 ID。关闭 Help 后 Main 仍然运行，关闭最后一个窗口则退出应用。

主窗口 ID 是 `main`，辅助窗口 ID 必须非空、唯一，且不能使用 `main`。ID 在代码中标识窗口，标题则用于显示。

## 按需创建窗口

保留可复用的 `WindowConfig`，在用户请求新窗口时调用 `WindowManager.create(id, config)`，不需要预先向 `App` 注册。例如，将上面的 `add_window` 调用替换为以下 setup 回调：

```moonbit
..setup(context => {
  let help = @proton.WindowConfig("Help", @proton.AppEntry::Html("<h1>Help</h1>"))
  let first = context.windows().create("help-1", help)
  let second = context.windows().create("help-2", help)
  println(first.id() + ", " + second.id())
})
```

每次调用都会创建独立的窗口、初始子视图和清理作用域。后续的命令处理器也可以通过保留的窗口管理器调用同一操作。每个存活窗口使用不同的 ID；创建已活动的 ID 会抛出 `AlreadyOpen`。关闭完成后可以复用 ID，但旧句柄仍然无效。

`single_instance()` 限制应用进程数量，不限制窗口数量；同一个运行时可以创建多个窗口，不需要为第二个窗口启动新的 Proton 运行时。

需要调用命令时，使用 `RendererTarget::entry(window="help-1")` 按 ID 授权，或使用 `RendererTarget::entry_prefix("help-")` 指定非空前缀。新窗口不会继承 `main` 的权限。参见[原生能力](capabilities.md)。

## 使用与释放句柄

`setup_window` 中的 `context.handle()` 返回当前 `WindowHandle`，可用于 `focus()`、`hide()`、`show()`、`close()` 等操作。浏览器操作通过 `handle.web_contents()` 获取。

清理闭包直接捕获窗口 ID。Todo 模板也以此方式移除保存的事件目标。获取窗口所属资源后立即注册清理，后续初始化失败时仍能释放资源。窗口重开后拥有新的清理作用域。关闭后停止使用原生句柄。

## 决定应用何时退出

默认策略是在最后一个窗口关闭后退出。托盘和后台应用可以加入：

```moonbit
..last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
```

此时关闭全部窗口不会结束进程。在实际应用采用该策略前，应先提供明确的退出操作。

需要异步决定是否允许关闭时，设置 `WindowConfig.close_handler`，返回 `WindowCloseDecision::Allow` 继续关闭，返回 `Deny` 保持窗口打开。确认对话框或未保存文档检查应放在这里，`context.add_cleanup` 则注册关闭后的清理。

## 平台相关的窗口行为

原生窗口装饰和可用控制项因平台而异。依赖平台专属方法前，请查询[窗口 API](https://github.com/moonbit-community/proton/blob/91ffc6210878af84a639d773efdc71669dc47430/proton/pkg.generated.mbti)。使用叠加标题栏时，需要一起处理前端标题栏布局与原生配置。

辅助页面也是独立的 capability 目标，只应授予其所需的宿主操作，见[原生能力](capabilities.md)。
