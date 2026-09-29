# Release Notes

## 0.3.4 — 2026-09-28

本书对应已发布的 [0.3.4 源码](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa)。[发布与 registry 验收工作流](https://github.com/moonbit-community/proton/actions/runs/36407926563)已成功完成。Warren 是独立依赖，仍使用 0.3.3。

- **生命周期：**新增应用退出拦截、强制退出、应用级窗口／浏览器／会话事件及焦点和显隐控制。修复 will_quit 中强制退出、exit(0)、子视图 renderer 通知、页面恢复与关闭记录回收。
- **通信：**保留命令错误码，区分业务命令失败与运行时失败，移除全局待响应请求数量上限。扩展操作清单从绑定生成。
- **浏览器 API：**增加导航历史和插入 CSS 控制；任务指标明确区分 CEF task 和进程。
- **平台与打包：**修复 Windows 桌面媒体授权及子视图布局、macOS 查询的 autorelease pool 和错误弹窗布局；完善打包锁，提供显式最低 macOS 版本元数据，保留 AppImage 中 helper 的可执行权限。
- **CLI：**new 不再对已经显式提供的选项重复询问。async 升级至 0.22.4。

### 应用升级

CLI 和应用的 proton_* 模块统一使用 0.3.4，并执行 `proton_cli cef setup` 安装匹配的 helper。重新安装 CLI 不会重写已有项目。

曾短暂引入的 app_metrics 改为 `task_metrics` 与 `AppTaskMetric`：任务身份不是进程身份，不同任务的 `hosting_process_usage` 可能重复，不能直接相加作为应用总用量。参见 [PR #412](https://github.com/moonbit-community/proton/pull/412)。[PR #408](https://github.com/moonbit-community/proton/pull/408)删除了未使用的旧命令配置 API；应用命令继续通过绑定注册。

## 0.3.3 — 2026-09-21

- **视图生命周期：**移除或显式关闭子视图后，保留投递最终关闭事件所需的实例身份。覆盖浏览器创建前关闭、替换后的旧事件等情况。[PR #378](https://github.com/moonbit-community/proton/pull/378)
- **依赖更新：**async 0.22.1、x 0.5.5、lexer/parser/moon_config 0.4.0、Rabbita 0.16.2、Warren 0.3.3。模板默认版本同步更新，取消处理与受保护的清理适配 async 新语义。[PR #379](https://github.com/moonbit-community/proton/pull/379)
- **发布：**所有工作区模块统一升级到 0.3.3，CEF 引擎版本不变。[发布 PR](https://github.com/moonbit-community/proton/pull/380) · [成功发布记录](https://github.com/moonbit-community/proton/actions/runs/35577888216)

### 应用升级

应用的 `proton_*` 依赖和 CLI 统一使用 0.3.3。已有项目保留原配置和源码，安装新版 CLI 不会重写它们。使用 isomorphic 前端时安装 Warren 0.3.3，构建前运行 `proton_cli cef setup` 安装匹配的 helper。

直接使用 async 的应用需要关注 0.22 的取消语义：取消不再作为普通错误被捕获。等待已取消任务的 `wait()` 可以报告 `TaskCancelled`；子进程关闭则可以在完成回收后返回退出结果。

### 更早的发布历史

更早的变更见 [0.3.2 发布准备](https://github.com/moonbit-community/proton/pull/377)和[仓库历史](https://github.com/moonbit-community/proton/commits/main/)。本页从 0.3.3 开始记录详细发布说明。
