# 后台驻留

单实例应用在最后一个窗口关闭后继续运行。

[57_background_residency](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/57_background_residency) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/57_background_residency/main.mbt)

## 行为

KeepRunning 保留进程。再次启动发送 Reopen，处理器仅在 main 不存在时重建窗口。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 57_background_residency --target native
```

## 限制与使用边界

关闭窗口有意不退出进程。结束应用需使用平台 Quit 操作或停止开发命令，这与默认的最后窗口关闭策略不同。

## 关键代码与设计

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
async fn main {
  @proton.html("Background Residency", page, width=760, height=480)
  .identifier("com.example.proton.background-residency")
  .single_instance()
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .on_launch_input(async fn(context, input) noraise {
    if input is Reopen && context.windows().find("main") is None {
      ignore(context.windows().open("main")) catch {
        error => println("failed to reopen main window: " + error.to_string())
      }
    }
  })
  .run_or_abort()
}
```

KeepRunning 修改最后窗口关闭后的行为，single_instance 将后续启动转发给现有进程。收到 Reopen 后先检查 main 是否存在，不存在时才创建新实例。关闭窗口与退出应用是两个刻意区分的操作。

真实后台应用需要可访问的显式 Quit 入口，例如托盘命令。停止开发进程属于强制终止，不能证明正常生命周期清理。Reopen 创建新窗口实例，不应保留之前的句柄。
