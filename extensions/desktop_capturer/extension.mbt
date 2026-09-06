///|
let get_sources_command = @desktop_capturer_contract.get_sources

///|
fn source_from_display(
  d : @sys_screen_monitor.DisplayInfo,
) -> @desktop_capturer_contract.Source {
  @desktop_capturer_contract.Source::{
    id: "screen:" + d.id.to_string(),
    name: if d.is_primary {
      "Entire Screen"
    } else {
      "Display " + d.id.to_string()
    },
    display_id: d.id.to_string(),
    thumbnail: None,
  }
}

///|
#proton.command(contract=get_sources_command)
fn get_sources(
  request : @desktop_capturer_contract.GetSourcesRequest,
) -> @desktop_capturer_contract.GetSourcesReply raise DesktopCapturerError {
  guard request.types.length() > 0 else {
    raise Unsupported(
      operation="getSources",
      detail="at least one source type is required",
    )
  }
  for source_type in request.types {
    if source_type == "window" {
      raise Unsupported(
        operation="window",
        detail="window sources are not available in the initial desktopCapturer slice",
      )
    }
    if source_type != "screen" {
      raise Unsupported(
        operation="source type",
        detail="only the screen source type is currently supported",
      )
    }
  }
  match request.thumbnail_width {
    Some(width) if width <= 0 =>
      raise QueryFailed(detail="thumbnail width must be positive when supplied")
    _ => ()
  }
  match request.thumbnail_height {
    Some(height) if height <= 0 =>
      raise QueryFailed(
        detail="thumbnail height must be positive when supplied",
      )
    _ => ()
  }
  let monitor = @sys_screen_monitor.ScreenMonitor() catch {
    error => raise QueryFailed(detail=error.to_string())
  }
  let displays = monitor.displays() catch {
    error => {
      monitor.destroy()
      raise QueryFailed(detail=error.to_string())
    }
  }
  monitor.destroy()
  @desktop_capturer_contract.GetSourcesReply::{
    sources: displays.map(source_from_display),
  }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @desktop_capturer_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}

///|
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
