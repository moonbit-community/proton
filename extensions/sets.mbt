// The updater extension is deliberately not in either set. Registering it
// hands a page the ability to start a download and replace the installed
// application, and that is a decision an application makes for itself — not
// something it acquires by asking for "all the built-in extensions".

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
