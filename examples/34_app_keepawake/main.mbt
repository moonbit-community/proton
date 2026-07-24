///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit App Runtime + Keep Awake",
      resource,
      width=920,
      height=680,
      debug=true,
    ).extension(@keepawake.extension())
    app.run_or_abort()
  })
}
