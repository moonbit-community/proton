///|
/// Returns every built-in Lepus extension.
pub fn all() -> @lepus_extension.Extensions {
  @lepus_extension.extensions([
    @fs.extension(),
    @path.extension(),
    @dialog.extension(),
    @clipboard.extension(),
    @shell.extension(),
    @notification.extension(),
    @tray.extension(),
    @global_hotkey.extension(),
    @auto_launch.extension(),
    @keepawake.extension(),
    @microphone.extension(),
  ])
}

///|
/// Returns built-in desktop integration extensions.
pub fn desktop() -> @lepus_extension.Extensions {
  @lepus_extension.extensions([
    @dialog.extension(),
    @clipboard.extension(),
    @shell.extension(),
    @notification.extension(),
    @tray.extension(),
    @global_hotkey.extension(),
    @auto_launch.extension(),
    @keepawake.extension(),
    @microphone.extension(),
  ])
}
