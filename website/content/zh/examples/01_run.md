# 最小应用

内联 HTML 与原生应用入口。

[01_run](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/01_run) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/01_run/main.mbt)

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

## 关键代码与设计

HTML 是直接传给应用构建器的 MoonBit 值，本页面无需前端服务器、资源查找或命令通信。显式 identifier 为直接运行仓库示例提供应用身份；scaffold 则通过 load_config() 读取身份。

适合复用为小型自包含页面；需要独立构建的 CSS／JavaScript 时应改用资源入口。debug=true 是示例选择，不是分发要求。
