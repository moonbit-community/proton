# 窗口与浏览器视图

[English](../windows.html)

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

完整签名和选项见[窗口 API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/)。可运行练习位于独立的[多窗口教程](tutorial/windows.md)。
