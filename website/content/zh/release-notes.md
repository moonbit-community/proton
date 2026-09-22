# Release Notes

[English](../release-notes.html)

## 0.3.3 — 2026-09-21

- **视图生命周期：**移除或显式关闭子视图后，保留投递最终关闭事件所需的实例身份。覆盖浏览器创建前关闭、替换后的旧事件等情况。[PR #378](https://github.com/moonbit-community/proton/pull/378)
- **依赖更新：**async 0.22.1、x 0.5.5、lexer/parser/moon_config 0.4.0、Rabbita 0.16.2、Warren 0.3.3。模板默认版本同步更新，取消处理与受保护的清理适配 async 新语义。[PR #379](https://github.com/moonbit-community/proton/pull/379)
- **发布：**所有工作区模块统一升级到 0.3.3，CEF 引擎版本不变。[发布 PR](https://github.com/moonbit-community/proton/pull/380) · [成功发布记录](https://github.com/moonbit-community/proton/actions/runs/35577888216)

### 应用升级

应用的 `proton_*` 依赖和 CLI 统一使用 0.3.3。已有项目保留原配置和源码，安装新版 CLI 不会重写它们。使用 isomorphic 前端时安装 Warren 0.3.3，构建前运行 `proton_cli cef setup` 安装匹配的 helper。

直接使用 async 的应用需要关注 0.22 的取消语义：取消不再作为普通错误被捕获。等待已取消任务的 `wait()` 可以报告 `TaskCancelled`；子进程关闭则可以在完成回收后返回退出结果。

### 更早的发布历史

更早的变更见 [0.3.2 发布准备](https://github.com/moonbit-community/proton/pull/377)和[仓库历史](https://github.com/moonbit-community/proton/commits/main/)。本页从 0.3.3 开始记录详细发布说明。
