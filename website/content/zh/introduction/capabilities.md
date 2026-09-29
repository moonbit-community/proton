# 扩展与能力

扩展注册可复用的宿主操作。渲染器能力安装扩展后端，并向指定渲染器目标授予权限范围。添加 `proton_ext` 模块依赖仅使代码可用，不安装处理器，也不授予访问权限。

## 注册与目标

`App.capability(capability, targets?)` 配置安装与访问范围。不指定 targets 时，授权作用于主入口。`RendererTarget.entry(window=...)` 和 `RendererTarget.bundled(window=...)` 选择命名窗口的入口或打包页面目标。窗口属于同一个应用，不代表其权限自动变为全局。

应用命令使用 `app:` 路由，扩展操作使用 `ext:<extension>/<operation>`。JavaScript 通过 `window.__MoonBit__.core.invokeOp(route, request)` 调用已安装操作，返回 Promise。

## 文件系统权限范围

`proton_ext/fs.capability` 接收 `PermissionRoot`，每项将一个宿主目录与允许的操作绑定。范围由后端配置，渲染器请求不能扩大它。

| 属性 | 行为 |
| --- | --- |
| 相对根路径或请求路径 | 相对于 `resource_dir()` 解析 |
| 超出授权根目录的路径 | 拒绝，包括符号链接逃逸 |
| 根目录授权中没有列出的操作 | 不被该授权允许 |
| 文本载荷 | UTF-8 |

文件系统操作包括 `read_file`、`write_file`、`mkdir`、`readdir`、`remove`、`rmdir`、`rename`、`realpath`、`exists`、`kind` 和 `size`。扩展内部将规范路径检查和操作串行执行。

## 可用性与错误

缺少能力声明时，路由不可用。扩展已安装时，仍可能因权限范围、参数、平台限制或操作系统错误拒绝请求。这些错误通过命令 bridge 报告；安装不意味着所有原生操作必然成功。

文件系统、对话框、剪贴板、shell、托盘等能力使用不同的范围类型，平台覆盖也不同。0.3.4 的通知扩展面向 macOS。框架支持的平台列表不等同于各能力的支持矩阵。

完整构建器及请求／响应类型见[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)。完整练习位于独立的[文件访问教程](../tutorial/capabilities.md)。

## 平台差异与选择

以下是 0.3.4 已实现能力的主要边界，不承诺缺少桌面服务时仍可用：

| 能力 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| 文件、路径、宿主 HTTP、子进程 | 支持 | 支持 | 支持 |
| 原生对话框、文本剪贴板 | 支持 | 支持 | 依赖桌面会话／GTK 等后端 |
| 系统通知扩展 | 支持 | 未实现 | 未实现 |
| 托盘 | 菜单及平台事件 | 点击、右击、双击和菜单 | 依赖 AppIndicator／Ayatana 与桌面会话 |
| 桌面来源与缩略图 | 显示器；缩略图需要屏幕录制权限 | 可见有标题窗口及 GDI 缩略图 | X11/RandR 显示器；缩略图为 null |

capability 授权与操作系统授权不同。声明屏幕或媒体能力不会自动获得系统隐私权限；系统拒绝、后端不可用与应用未授权应分别处理。托盘等提供 support 查询的能力应先检查支持情况，菜单事件也比各平台鼠标手势更可移植。

net 扩展在宿主执行 HTTP 请求，返回状态、响应头及 UTF-8 文本；它不等于浏览器 fetch，不共享浏览器 cookie jar，也不自动跟随重定向。二进制数据不是该文本响应接口的无损用途。process 扩展创建的进程属于扩展应用生命周期，wait 回收句柄，kill 后仍需 wait，应用退出会取消并回收剩余子进程。

完整扩展清单及各范围类型见[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)。访问某个 API 前分别确认：目标授权、操作系统授权、平台后端支持。
