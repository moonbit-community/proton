///|
let window : Ref[@proton.WindowHandle?] = Ref(None)

///|
let set_overlay : @proton_contract.Command[Int32, Json] = @proton_contract.command(
  "set-overlay",
)

///|
let set_fullscreen : @proton_contract.Command[Bool, Json] = @proton_contract.command(
  "set-fullscreen",
)

///|
fn overlay_area(handle : @proton.WindowHandle) -> Json raise {
  match handle.titlebar_area() {
    Some(area) => area.to_json()
    None => Json::null()
  }
}

///|
fn register_overlay_commands(
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  registrar.bind(set_overlay, (_context, height) => {
    let handle = window.val.unwrap()
    let overlay = if height == 0 {
      None
    } else {
      Some(@proton.TitlebarOverlay::{
        height,
        background_color: "#2b2b2b",
        symbol_color: "#f0f0f0",
      })
    }
    handle.set_titlebar_overlay(overlay)
    overlay_area(handle)
  })
  registrar.bind(set_fullscreen, (_context, fullscreen) => {
    let handle = window.val.unwrap()
    handle.set_fullscreen(fullscreen)
    overlay_area(handle)
  })
}

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
  ..debug(enabled=true)
  ..identifier("dev.proton.48-titlebar-overlay")
  ..commands(register_overlay_commands)
  ..setup_window(context => {
    window.val = Some(context.handle())
    context.add_cleanup(() => window.val = None)
  })
  .run_or_abort()
}
