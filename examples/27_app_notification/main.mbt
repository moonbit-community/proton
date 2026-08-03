///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit App Runtime + Notification",
      resource,
      width=940,
      height=720,
      debug=true,
    ).expose(@notification.extension())
    app.run_or_abort()
  })
}
