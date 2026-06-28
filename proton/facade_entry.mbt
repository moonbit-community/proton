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
      native_unit_result("load file", window.load_url(file_url(path)))
    @manifest.AppEntry::Asset(path) =>
      native_unit_result("load asset", window.load_url(file_url(path)))
  }
}

///|
fn inject_command_proxy_script(html : String, script : String?) -> String {
  match script {
    None => html
    Some(value) => {
      let tag = "<script>" +
        value.replace_all(old="</script", new="<\\/script") +
        "</script>\n"
      if html.contains("<head>") {
        html.replace(old="<head>", new="<head>\n" + tag)
      } else if html.contains("<body>") {
        html.replace(old="<body>", new=tag + "<body>")
      } else {
        tag + html
      }
    }
  }
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
