///|
async fn main {
  @proton.url(
    "Remote URL",
    "https://example.com/",
    width=800,
    height=600,
    debug=true,
  ).run_or_abort()
}
