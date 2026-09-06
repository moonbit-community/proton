///|
let get_sources_command = @desktop_capturer_contract.get_sources

///|
struct WindowSourcesWire {
  supported : Bool
  sources : Array[WindowSourceWire]
  error : String?
} derive(FromJson)

///|
struct WindowSourceWire {
  id : String
  display_id : String
  x : Int
  y : Int
  width : Int
  height : Int
  thumbnail : String?
  name : String
} derive(FromJson)

///|
fn window_source_from_wire(
  source : WindowSourceWire,
) -> @desktop_capturer_contract.Source {
  @desktop_capturer_contract.Source::{
    id: source.id,
    name: source.name,
    display_id: source.display_id,
    x: source.x,
    y: source.y,
    width: source.width,
    height: source.height,
    thumbnail: source.thumbnail,
  }
}

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
    x: d.bounds.x,
    y: d.bounds.y,
    width: d.bounds.width,
    height: d.bounds.height,
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
  let wants_windows = Ref(false)
  let wants_screens = Ref(false)
  for source_type in request.types {
    if source_type == "window" {
      wants_windows.val = true
    }
    if source_type == "screen" {
      wants_screens.val = true
    }
    if source_type != "screen" && source_type != "window" {
      raise Unsupported(
        operation="source type",
        detail="only the screen and window source types are currently supported",
      )
    }
  }
  match request.thumbnail_width {
    Some(width) if width <= 0 =>
      raise QueryFailed(detail="thumbnail width must be positive when supplied")
    Some(width) if width > 4096 =>
      raise QueryFailed(detail="thumbnail width must not exceed 4096")
    _ => ()
  }
  match request.thumbnail_height {
    Some(height) if height <= 0 =>
      raise QueryFailed(
        detail="thumbnail height must be positive when supplied",
      )
    Some(height) if height > 4096 =>
      raise QueryFailed(detail="thumbnail height must not exceed 4096")
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
  let screen_sources = if wants_screens.val {
    displays.map(source_from_display)
  } else {
    []
  }
  let window_sources = if wants_windows.val {
    let thumbnail_width = request.thumbnail_width.unwrap_or(0)
    let thumbnail_height = request.thumbnail_height.unwrap_or(0)
    let text = @utf8.decode_lossy(
      monitor.window_sources_json(thumbnail_width, thumbnail_height)[:],
    )
    let wire : WindowSourcesWire = @json.from_json(@json.parse(text)) catch {
      _ => raise QueryFailed(detail="native window source payload is invalid")
    }
    if !wire.supported {
      raise Unsupported(
        operation="window",
        detail=wire.error.unwrap_or("window sources are unavailable"),
      )
    }
    wire.sources.map(window_source_from_wire)
  } else {
    []
  }
  monitor.destroy()
  @desktop_capturer_contract.GetSourcesReply::{
    sources: screen_sources + window_sources,
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
