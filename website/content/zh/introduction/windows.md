# 窗口与浏览器视图

窗口声明属于 `App`，运行中的窗口操作属于 `WindowHandle`。浏览器导航和开发者工具属于 `BrowserHandle`，通过 `WindowHandle.browser()` 获取。

## 标识与声明

主窗口 ID 为 `main`。`App.add_window(id, title, entry, ...)` 声明附加窗口，其 ID 必须非空、唯一，且不能为 `main`。标题是显示文本，不是窗口标识。

附加窗口默认在启动时打开。`open_on_start=false` 将打开推迟到 `WindowManager.open(id)`。`ApplicationContext.windows()` 和 `WindowContext.windows()` 提供窗口管理器。所有窗口属于同一个应用运行时。

## 运行时操作

| 领域 | `WindowHandle` 操作 |
| --- | --- |
| 显示与焦点 | `show`、`hide`、`focus`、`is_visible`、`is_focused` |
| 几何 | `bounds`、`set_bounds`、`position`、`set_position`、`content_size`、`set_content_size` |
| 窗口状态 | `minimize`、`maximize`、`restore`、`set_fullscreen` |
| 外观 | `set_theme`、`set_background_color`、`set_title`、`set_menu` |
| 生命周期 | `close` |

原生操作可能抛出 `WindowSessionError`。句柄不是永久有效的：窗口关闭时，应释放窗口所属状态以及保留的事件目标。隐藏的窗口仍然存活。

## 关闭语义

`App.on_window_close_request` 注册异步回调；回调接收窗口句柄，返回 `WindowCloseDecision::Allow` 或 `Deny`。`window_lifecycle.on_close` 是关闭后的清理钩子，不能否决关闭。最后窗口关闭策略默认为 `Quit`；`KeepRunning` 让应用在无窗口时继续运行，需要应用提供显式退出入口。参见[应用生命周期](lifecycle.md)。

## 子浏览器视图

`App.with_view` 在主窗口声明视图；`WindowHandle.add_view` 动态创建视图并返回 `ViewHandle`。视图是窗口内部承载的子浏览器，不是第二个顶层窗口。其边界以左上角为原点，显示状态和 z-order 独立于主页面。`remove_view` 移除子视图。关闭父窗口也必须完成子浏览器销毁。

## 平台行为

`WindowThemePreference` 控制窗口主题，`system_appearance()` 返回系统外观，二者是不同概念。标题栏样式和原生控件因平台而异。红绿灯位置设置适用于 macOS；使用叠加标题栏时，前端布局需要考虑原生控件占用的空间。

完整签名和选项见[窗口 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。可运行练习位于独立的[多窗口教程](../tutorial/windows.md)。

## 打开操作与实例身份

`WindowManager.open(id)` 是异步操作，返回已激活的 WindowHandle。id 选择窗口声明，不是以后每次原生实例的永久身份。关闭并重新打开后，应通过 open 或 find 获取新句柄，旧句柄不会重新有效。

激活提交前取消调用，会丢弃排队的打开操作，或关闭该操作已经创建的实例。激活成功提交后，窗口属于应用，随后取消调用方不会把它关闭。未知声明和无效窗口状态产生窗口会话错误；任务取消遵循 async 的取消语义。

hide() 保留窗口实例、浏览器和相关任务。close() 发起销毁流程且可能被拒绝，不能把关闭请求当作清理完成。窗口状态应由生命周期清理释放，而不是刚请求关闭就释放。

## 浏览器与子视图边界

主页面通过 WindowHandle.browser() 操作，子页面通过 ViewHandle 操作。子视图导航或移除不会导航或关闭主页面。应用级创建和 renderer 终止回调以 WebContentsHandle 统一表示两者。

on_render_process_gone 同时覆盖主页面和子视图，无需额外订阅 on_view_event。renderer 终止会使页面工作失效，但不等于正常关闭窗口。应用根据终止详情决定重新加载还是展示恢复界面，并在导航后重新建立页面订阅。

视图坐标以父窗口内容区左上角为原点。固定声明不提供自动布局；布局变化时由应用更新边界。移除视图结束其浏览器生命周期，关闭父窗口也会销毁子视图。
