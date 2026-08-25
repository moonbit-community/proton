///|
async fn main {
  @proton.url(
    "Remote URL",
    "https://example.com/",
    width=800,
    height=600,
    debug=true,
  )
  .identifier("dev.proton.03-remote")
  .run_or_abort()
}
