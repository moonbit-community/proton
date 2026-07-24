///|
fn main {
  @proton.run(() => {
    @proton.file(
      "Local File",
      "02_local/app.html",
      width=800,
      height=600,
      debug=true,
    ).run_or_abort()
  })
}
