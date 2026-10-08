# 原生应用菜单

本例创建原生应用菜单，并在窗口运行期间更新菜单项状态。菜单操作通过存活的窗口句柄执行，窗口关闭时清除该引用。

[49_app_menu](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/49_app_menu) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/49_app_menu/main.mbt)

## 行为

菜单操作更新 enabled、visible、checked 状态。原生角色与应用命令在 MoonBit 中声明。

## 实现说明

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
async fn main {
  @proton.html(
    "App Menu State Review",
    html(),
    width=900,
    height=640,
    debug=true,
  )
  .menu(menu_bar())
  .identifier("dev.proton.49-app-menu")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
```

菜单是构建器配置的原生 UI。命令处理器通过有效窗口句柄修改或查询状态。ready 钩子保存句柄，close 钩子清空它，避免后续命令继续使用已关闭实例。

稳定的菜单命令 id 应与翻译标签分离。原生 role 项交给平台处理标准行为，应用命令项由应用处理。多窗口应用应将示例的单一 window slot 改为明确的每窗口所有权。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 49_app_menu --target native
```

## 限制与使用边界

菜单位置与角色支持取决于桌面平台。菜单事件可能没有聚焦窗口，处理器需要考虑这种情况。
