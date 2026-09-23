# 后台驻留

单实例应用在最后一个窗口关闭后继续运行。

[57_background_residency](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/57_background_residency) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/57_background_residency/main.mbt)

## 行为

KeepRunning 保留进程。再次启动发送 Reopen，处理器仅在 main 不存在时重建窗口。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 57_background_residency --target native
```

## 限制与使用边界

关闭窗口有意不退出进程。结束应用需使用平台 Quit 操作或停止开发命令，这与默认的最后窗口关闭策略不同。
