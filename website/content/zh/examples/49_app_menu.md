# 原生应用菜单

[English](../../examples/49_app_menu.html)

类型化菜单、动态命令状态与应用回调。

[49_app_menu](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/49_app_menu) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/49_app_menu/main.mbt)

## 行为

菜单操作更新 enabled、visible、checked 状态。原生角色与应用命令在 MoonBit 中声明。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 49_app_menu --target native
```

## 限制与使用边界

菜单位置与角色支持取决于桌面平台。菜单事件可能没有聚焦窗口，处理器需要考虑这种情况。
