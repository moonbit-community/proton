# 多窗口命令

[English](../../examples/45_bridge_multi_window.html)

多个窗口共用类型化命令注册。

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/45_bridge_multi_window) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/45_bridge_multi_window/main.mbt)

## 行为

identify 命令返回传入标签与 CommandContext.window_id()。不同窗口的请求保留各自来源身份。

## 运行

需满足[运行环境要求](../installation.md)。在仓库根目录执行：

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## 限制与使用边界

可选 delay_ms 便于观察并发请求。逻辑窗口名标识应用窗口，不是可以无限复用的原生句柄。
