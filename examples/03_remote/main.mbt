///|
async fn main {
  @proton.install_event_loop()
  @proton.url(
    "Remote URL",
    "https://example.com/",
    width=800,
    height=600,
    debug=true,
  ).run_or_abort()
}
