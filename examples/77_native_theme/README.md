# Native Theme

This is a manual review example for Proton's Electron-style `nativeTheme`
surface: the appearance query, `themeSource`, and the change event.

Run it with:

```sh
moon -C examples run 77_native_theme --target native
```

Review the application:

1. The summary shows the snapshot returned by `native_theme()`: dark colors,
   high contrast, and the application theme source.
2. Switch the operating system appearance (Windows: Settings > Personalization >
   Colors > Choose your mode; macOS: System Settings > Appearance; Linux: your
   desktop's light/dark preference). The window title bar, the summary, and a
   new **updated event** entry should follow, without restarting the app.
3. Turn on the operating system high contrast option. The summary should report
   increased contrast and another updated event should appear.
4. Choose **themeSource: light** and **themeSource: dark**. The application
   snapshot, the window chrome, and the source metric should follow, and each
   change should add an updated event. **Theme source: system** restores the
   operating system value.
5. Choose **Read back**. The snapshot is re-read from the native query and
   pushed back into the page, so the page only ever shows applied state.
6. Watch the renderer note at the bottom. It reports `prefers-color-scheme`,
   which keeps following the operating system even while `themeSource`
   overrides the application snapshot. That difference is intentional: the
   current CEF public API exposes no renderer color-scheme override, and
   `WindowHandle::set_window_theme` stays authoritative for one window's chrome.

Electron parity notes: `native_theme()` mirrors `nativeTheme.shouldUseDarkColors`,
`shouldUseHighContrastColors`, and `themeSource`; `native_theme_set_source`
mirrors assigning `nativeTheme.themeSource`; `on_native_theme_change` mirrors
`nativeTheme.on("updated")`. Electron hands that event no payload, while Proton
passes the new snapshot so a handler never has to read a value that has already
moved on.
