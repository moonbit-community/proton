///|
fn load_entry_after_create(
  window : @native.Window,
  entry : @manifest.AppEntry,
  command_proxy_script : String?,
) -> Result[Unit, String] {
  match entry {
    @manifest.AppEntry::Html(html) =>
      native_unit_result(
        "load html",
        window.load_html(
          inject_command_proxy_script(html, command_proxy_script),
          "proton://app/",
        ),
      )
    @manifest.AppEntry::Url(url) =>
      native_unit_result("load url", window.load_url(url))
    @manifest.AppEntry::File(path) =>
      load_file_entry_after_create(
        window, "load file", path, command_proxy_script,
      )
    @manifest.AppEntry::Asset(path) =>
      load_file_entry_after_create(
        window, "load asset", path, command_proxy_script,
      )
  }
}

///|
fn inject_command_proxy_script(html : String, script : String?) -> String {
  match script {
    None => html
    Some(value) => inject_html_bootstrap(html, script_tag(value))
  }
}

///|
fn load_file_entry_after_create(
  window : @native.Window,
  action : String,
  path : String,
  command_proxy_script : String?,
) -> Result[Unit, String] {
  match command_proxy_script {
    None => native_unit_result(action, window.load_url(file_url(path)))
    Some(script) =>
      match read_file_entry_html(path, action) {
        Err(error) => Err(error)
        Ok(html) => {
          let bootstrap = base_tag(asset_base_url(path)) + script_tag(script)
          native_unit_result(
            action,
            window.load_html(
              inject_html_bootstrap(html, bootstrap),
              asset_document_url(path),
            ),
          )
        }
      }
  }
}

///|
fn read_file_entry_html(
  path : String,
  action : String,
) -> Result[String, String] {
  try @mbfs.read_file_to_string(path) catch {
    error =>
      Err(
        action +
        " failed: failed to read HTML entry: " +
        @debug.render(@debug.to_repr(error)),
      )
  } noraise {
    text => Ok(text)
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
fn script_tag(script : String) -> String {
  "<script>" +
  script.replace_all(old="</script", new="<\\/script") +
  "</script>\n"
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
fn native_unit_result(
  action : String,
  result : Result[Unit, @native.NativeError],
) -> Result[Unit, String] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(native_error_message(action, error))
  }
}

///|
fn native_error_message(action : String, error : @native.NativeError) -> String {
  action +
  " failed: native error " +
  error.status.to_string() +
  ": " +
  error.message
}

///|
fn file_url(path : String) -> String {
  if path.has_prefix("file://") {
    path
  } else {
    let file_path : @mbpath.Path = path
    let normalized = file_path
      .resolve()
      .to_string()
      .replace_all(old="\\", new="/")
    if normalized.has_prefix("/") {
      "file://" + normalized
    } else {
      "file:///" + normalized
    }
  }
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
