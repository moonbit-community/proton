///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit Async Add Extension",
      resource,
      width=840,
      height=560,
      debug=true,
    ).extension(extension())
    app.run_or_abort()
  })
}
