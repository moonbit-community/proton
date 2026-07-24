///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
        "MoonBit System Runtime",
        resource,
        width=1080,
        height=760,
        debug=true,
      )
      .extension(@tray.extension())
      .extension(@notification.extension())
      .extension(@global_hotkey.extension())
    app.run_or_abort()
  })
}
