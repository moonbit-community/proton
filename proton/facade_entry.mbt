///|
fn load_entry_after_create(
  window : @native.Window,
  entry : @manifest.AppEntry,
) -> Unit raise AppEntryError {
  match entry {
    @manifest.AppEntry::Html(html) =>
      window.load_html(html, "proton://app/") catch {
        error => raise NativeLoad(action="load html", error~)
      }
    @manifest.AppEntry::Url(url) =>
      window.load_url(url) catch {
        error => raise NativeLoad(action="load url", error~)
      }
    @manifest.AppEntry::File(path) =>
      load_file_entry_after_create(window, "load file", path)
    @manifest.AppEntry::Asset(path) =>
      load_file_entry_after_create(window, "load asset", path)
  }
}

///|
fn load_file_entry_after_create(
  window : @native.Window,
  action : String,
  path : String,
) -> Unit raise AppEntryError {
  let html = read_file_entry_html(path)
  window.load_html(
    inject_html_bootstrap(html, base_tag(asset_base_url(path))),
    asset_document_url(path),
  ) catch {
    error => raise NativeLoad(action~, error~)
  }
}

///|
fn read_file_entry_html(path : String) -> String raise AppEntryError {
  @mbfs.read_file_to_string(path) catch {
    error =>
      raise ReadFailed(path~, detail=@debug.render(@debug.to_repr(error)))
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
fn asset_base_url(path : String) -> String {
  let document_url = asset_document_url(path)
  match document_url.rev_find("/") {
    Some(index) => document_url[:index + 1].to_owned()
    None => document_url
  }
}

///|
fn asset_document_url(path : String) -> String {
  let file_path : @mbpath.Path = path
  let normalized = file_path
    .resolve()
    .to_string()
    .replace_all(old="\\", new="/")
  "proton://app/" + asset_url_path_encode(normalized)
}

///|
fn asset_url_path_encode(path : String) -> String {
  let bytes = @utf8.encode(path)
  let builder = StringBuilder::new(size_hint=bytes.length())
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
fn debug_port(debug : Int) -> Int {
  if debug > 0 {
    match @env.get_env_var("PROTON_REMOTE_DEBUGGING_PORT") {
      Some(value) => {
        let port = @string.parse_int(value[:]) catch { _ => 9222 }
        if port > 0 {
          port
        } else {
          9222
        }
      }
      None => 9222
    }
  } else {
    0
  }
}

///|
fn size_hint_from_resizable(resizable : Bool) -> @manifest.WindowSizeHint {
  if resizable {
    @manifest.WindowSizeHint::None
  } else {
    @manifest.WindowSizeHint::Fixed
  }
}
