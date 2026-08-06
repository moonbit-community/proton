///|
async fn main {
  @proton.install_event_loop()
  @proton.html("17 extension", resource, width=800, height=600, debug=true).run_or_abort()
}
