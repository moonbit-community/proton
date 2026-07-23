///|
fn main {
  @proton.run(() => {
    @proton.html(
      "01 tauri like helloworld",
      resource,
      width=800,
      height=600,
      debug=true,
    ).run_or_abort()
  })
}
