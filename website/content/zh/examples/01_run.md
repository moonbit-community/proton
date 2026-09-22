# 最小应用

[English](../../examples/01_run.html)

内联 HTML 与原生应用入口。

[01_run](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/01_run) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/01_run/main.mbt)

## 行为

单个 800 × 600 窗口显示“01 run”。构建器声明应用身份并启动应用。

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>01 run</title></head>
    #|  <body><h1>01 run</h1></body>
    #|</html>
  @proton.html("01 run", html, width=800, height=600, debug=true)
  .identifier("dev.proton.01-run")
  .run_or_abort()
}
```

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 01_run --target native
```

## 限制与使用边界

适合将运行时安装问题与前端工具问题分开排查。此示例没有命令交互或外部资源加载。
