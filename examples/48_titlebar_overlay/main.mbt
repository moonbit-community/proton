///|
async fn main {
  @proton.html("Proton Overlay", resource, width=1000, height=640, debug=true)
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .run_or_abort()
}
