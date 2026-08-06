///|
async fn main {
  @proton.install_event_loop()
  @proton.html("12 embed", resource, width=800, height=600, debug=true).run_or_abort()
}
