///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "Proton Attribute Codegen",
      resource,
      width=840,
      height=560,
      debug=true,
    ).extension(extension())
    app.run_or_abort()
  })
}
