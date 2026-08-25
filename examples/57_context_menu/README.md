# Window Context Menu

This is a manual review example for Proton's Electron-style window context
menu API.

- Right-click the large surface to pass `MouseEvent.clientX/clientY` to
  `Menu::popup(window, x, y)`.
- Use the button to check an explicit coordinate popup.
- Check command events, separators, a nested submenu, and a standard `SelectAll`
  role item.

Run it with:

```sh
moon -C examples run 57_context_menu --target native
```

Windows currently reports native popup menus as unsupported, matching Proton's
native application-menu behavior on that platform.
