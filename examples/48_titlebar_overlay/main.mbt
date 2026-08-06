///|
async fn main {
  @proton.html("Proton Overlay", resource, width=800, height=520, debug=true)
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .run_or_abort()
}
