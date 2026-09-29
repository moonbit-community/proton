# 多窗口命令

多个窗口共用类型化命令注册。

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/45_bridge_multi_window) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/45_bridge_multi_window/main.mbt)

## 行为

identify 命令返回传入标签与 CommandContext.window_id()。不同窗口的请求保留各自来源身份。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## 限制与使用边界

可选 delay_ms 便于观察并发请求。逻辑窗口名标识应用窗口，不是可以无限复用的原生句柄。

## 关键代码与设计

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
  .capability(@proton_extension.capability(multi_window_extension()), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
  ])
  .app_lifecycle(
    on_start=async fn(context) { ignore(context.windows().open("secondary")) },
    on_shutdown=fn(_state) {  },
  )
  .identifier("dev.proton.45-bridge-multi-window")
  .run_or_abort()
}
```

同一扩展实现服务两个独立授权的 renderer 目标。secondary 声明使用 open_on_start=false，由应用启动钩子显式打开。处理器返回 context.window_id()，说明调用方身份来自宿主上下文，而非页面传来的 label。

可以复用业务处理器，但必须显式列出目标。每窗口 UI 状态留在前端，共享状态由宿主管理。延迟调用可以重叠，不能按当前焦点窗口判断响应归属。
