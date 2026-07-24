///|
fn main {
  @proton.run(() => {
    @proton.html("12 embed", resource, width=800, height=600, debug=true).run_or_abort()
  })
}
