# 多窗口命令

本示例在同一个应用中按需创建窗口，并明确授权一组窗口 ID 调用命令。示例使用尚未发布的运行时创建 API。

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/main/examples/45_bridge_multi_window) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/main/examples/45_bridge_multi_window/main.mbt)

## 行为

identify 命令返回传入标签与 CommandContext.window_id()。不同窗口的请求保留各自来源身份。

## 实现说明

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
async fn main {
  let config = @proton.WindowConfig(
    "Bridge Multi B",
    @proton.AppEntry::Html(page_html("B")),
    width=520,
    height=420,
  )
  let windows : Ref[@proton.WindowManager?] = Ref(None)
  let next_id = Ref(0)
  let extension = multi_window_extension(() => {
    next_id.val += 1
    let id = "chat-" + next_id.val.to_string()
    ignore(windows.val.unwrap().create(id, config))
    id
  })
  @proton.html(
    "Bridge Multi A",
    page_html("A"),
    width=520,
    height=420,
    debug=true,
  )
  ..identifier("dev.proton.45-bridge-multi-window")
  ..single_instance()
  ..capability(@proton_extension.capability(extension), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
    @proton.RendererTarget::entry_prefix("chat-"),
  ])
  ..setup(context => {
    windows.val = Some(context.windows())
    ignore(context.windows().create("secondary", config))
  })
  .run_or_abort()
}
```

应用在 setup 中用 `WindowManager.create` 创建 `secondary`；每次点击 **New window**，再创建一个 `chat-N` 窗口。所有附加实例复用 `config`，浏览器状态和命令来源身份彼此独立，不需要窗口池或预先声明 ID。

扩展只注册一次。精确授权覆盖 `main` 和 `secondary`；`entry_prefix("chat-")` 授权新增聊天窗口的入口页面。处理器返回 `context.window_id()`，按宿主确认的调用方身份路由，而不是相信 JavaScript 传入的标签。`single_instance()` 保持单个应用进程，同时允许多个窗口。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## 限制与使用边界

可选 delay_ms 便于观察并发请求。逻辑窗口名标识应用窗口，不是可以无限复用的原生句柄。
