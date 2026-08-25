# Window Context Menu

This is a manual review example for Proton's Electron-style window context
menu API.

- Right-click the large surface to pass `MouseEvent.clientX/clientY` to
  `Menu::popup(window, x, y)`.
- Use the button to check an explicit coordinate popup.
- Check command events, separators, a nested submenu, and a standard `SelectAll`
  role item.
- On Windows with display scaling above 100%, confirm the popup stays aligned
  with the amber marker instead of drifting down and right.

Run it with:

```sh
moon -C examples run 58_context_menu --target native
```

The popup path is implemented with the platform-native menu surface on macOS,
Windows, and Linux.
