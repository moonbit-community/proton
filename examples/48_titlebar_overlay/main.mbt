///|
async fn main {
  @proton.App(
    @proton.WindowConfig(
      "Proton Overlay",
      @proton.AppEntry::Html(resource),
      titlebar_style=@proton.TitlebarStyle::Overlay,
      width=800,
      height=520,
    ),
  )
  .debug(enabled=true)
  .identifier("dev.proton.48-titlebar-overlay")
  .run_or_abort()
}
