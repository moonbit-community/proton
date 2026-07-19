///|
async fn main {
  @proton.file(
    "Proton Overlay",
    "48_titlebar_overlay/index.html",
    width=1000,
    height=640,
    debug=true,
  )
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .run_or_abort()
}
