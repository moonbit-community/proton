///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit App Runtime + Microphone",
      resource,
      width=1040,
      height=760,
      debug=true,
    ).expose(@microphone.extension())
    app.run_or_abort()
  })
}
