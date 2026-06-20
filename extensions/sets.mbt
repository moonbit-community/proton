///|
/// Returns every built-in Proton extension.
pub fn all() -> @proton_extension.Extensions {
  @proton_extension.extensions([
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
pub fn desktop() -> @proton_extension.Extensions {
  @proton_extension.extensions([
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
