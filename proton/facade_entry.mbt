///|
async fn prepare_entry(
  entry : @manifest.AppEntry,
) -> PreparedEntry raise AppEntryError {
  match entry {
    @manifest.AppEntry::Html(html) =>
      DocumentEntry(
        { url: asset_base_url(), content: @utf8.encode(html) },
        None,
      )
    @manifest.AppEntry::Url(url) => RemoteEntry(url)
    @manifest.AppEntry::File(path) =>
      prepare_file_entry(resolve_entry_path(path))
    @manifest.AppEntry::Asset(path) =>
      prepare_file_entry(resolve_asset_path(path))
  }
}

///|
async fn prepare_file_entry(
  resolved : @mbpath.Path,
) -> PreparedEntry raise AppEntryError {
  let resolved_text = resolved.to_string()
  let canonical = @async_fs.realpath(resolved_text) catch {
    error =>
      raise ReadFailed(path=resolved_text, detail=@debug.render(Repr(error)))
  }
  let html = @async_fs.read_file(canonical).text() catch {
    error => raise ReadFailed(path=canonical, detail=@debug.render(Repr(error)))
  }
  let document = ResourceDocument::{
    url: asset_document_url(resolved),
    content: @utf8.encode(
      inject_html_bootstrap(html, base_tag(asset_base_url())),
    ),
  }
  DocumentEntry(document, Some(@mbpath.Path(canonical).dirname().to_string()))
}

///|
fn load_prepared_entry(
  window : @native.Window,
  entry : PreparedEntry,
) -> Unit raise AppEntryError {
  let url = match entry {
    RemoteEntry(url) => url
    DocumentEntry(document, _) => document.url
  }
  window.load_url(url) catch {
    error => raise entry_platform_load_failed("load entry", error)
  }
}

///|
fn resolve_entry_path(path : String) -> @mbpath.Path {
  let native_path = if @mbpath.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
  @mbpath.Path(native_path).resolve()
}

///|
fn resolve_asset_path(path : String) -> @mbpath.Path {
  let native_path = if @mbpath.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
  let path : @mbpath.Path = native_path
  if path.is_absolute() {
    path.normalize()
  } else {
    @mbpath.Path(runtime_resource_dir()).join(native_path).normalize()
  }
}

///|
fn inject_html_bootstrap(html : String, bootstrap : String) -> String {
  if html.contains("<head>") {
    html.replace(old="<head>", new="<head>\n" + bootstrap)
  } else if html.contains("<body>") {
    html.replace(old="<body>", new=bootstrap + "<body>")
  } else {
    bootstrap + html
  }
}

///|
fn base_tag(href : String) -> String {
  "<base href=\"" + html_attribute_escape(href) + "\">\n"
}

///|
fn html_attribute_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn asset_base_url() -> String {
  "https://proton.localhost/"
}

///|
fn asset_document_url(path : @mbpath.Path) -> String {
  asset_base_url() + asset_url_path_encode(path.basename().to_owned())
}

///|
fn asset_url_path_encode(path : String) -> String {
  let bytes = @utf8.encode(path)
  let builder = StringBuilder(size_hint=bytes.length())
  for byte in bytes {
    if asset_url_path_byte_is_safe(byte) {
      builder.write_char(byte.to_char())
    } else {
      builder.write_char('%')
      builder.write_string(byte.to_hex())
    }
  }
  builder.to_string()
}

///|
fn asset_url_path_byte_is_safe(byte : Byte) -> Bool {
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'0' && byte <= b'9') ||
  byte == b'-' ||
  byte == b'.' ||
  byte == b'_' ||
  byte == b'~' ||
  byte == b'/' ||
  byte == b':'
}

///|
fn debug_level_from_bool(enabled : Bool) -> Int {
  if enabled {
    1
  } else {
    0
  }
}

///|
fn resolve_remote_debugging(
  debug : Int,
  configured_port : String?,
) -> @native.RemoteDebugging raise AppConfigurationError {
  guard debug > 0 else { return @native.RemoteDebugging::Disabled }
  let value = match configured_port {
    Some(value) => value.trim().to_owned()
    None => ""
  }
  guard value != "" else { return @native.RemoteDebugging::Ephemeral }
  let port = @string.parse_int(value[:]) catch {
    _ =>
      raise InvalidSetting(
        name="PROTON_REMOTE_DEBUGGING_PORT",
        message="must be 0 or an integer between 1024 and 65535",
      )
  }
  if port == 0 {
    @native.RemoteDebugging::Ephemeral
  } else if port >= 1024 && port <= 65535 {
    @native.RemoteDebugging::Fixed(port)
  } else {
    raise InvalidSetting(
      name="PROTON_REMOTE_DEBUGGING_PORT",
      message="must be 0 or an integer between 1024 and 65535",
    )
  }
}

///|
fn remote_debugging(
  debug : Int,
) -> @native.RemoteDebugging raise AppConfigurationError {
  resolve_remote_debugging(
    debug,
    @env.get_env_var("PROTON_REMOTE_DEBUGGING_PORT"),
  )
}

///|
fn size_hint_from_resizable(resizable : Bool) -> @manifest.WindowSizeHint {
  if resizable {
    @manifest.WindowSizeHint::None
  } else {
    @manifest.WindowSizeHint::Fixed
  }
}
