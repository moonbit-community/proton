// The updater extension is deliberately not in either set. Even though
// registration grants no renderer authority, installing the update backend is
// an application decision rather than part of a general desktop capability set.

///|
/// Returns every built-in Proton extension.
///
/// Not literally every one: see the note above about the updater.
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
    @power_monitor.extension(),
    @process.extension(),
    @net.extension(),
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
    @power_monitor.extension(),
    @process.extension(),
    @net.extension(),
  ])
}
