///|
fn bridge_name_valid(value : String) -> Bool {
  !value.is_empty() &&
  value.iter().all(c => c > ' ' && c < '\u007f' && c != '"' && c != '\\')
}

///|
fn validate_bridge_names(
  values : Array[String],
  description : String,
) -> Unit raise NativeError {
  let seen : Array[String] = []
  for value in values {
    if !bridge_name_valid(value) {
      raise invalid_argument(description + " is invalid")
    }
    if seen.length() >= 256 {
      raise invalid_argument(description + " list is too large")
    }
    if seen.contains(value) {
      raise invalid_argument(description + " is duplicated")
    }
    seen.push(value)
  }
}

///|
fn validate_bridge_config(config : BridgeConfig) -> Unit raise NativeError {
  if config.max_payload_bytes <= 0 || config.max_payload_bytes > 1048576 {
    raise invalid_argument("bridge max_payload_bytes is invalid")
  }
  let origins : Array[String] = []
  for grant in config.grants {
    let origin = grant.source_origin
    let authority = if origin.has_prefix("https://") {
      origin[8:].to_owned()
    } else if origin.has_prefix("http://") {
      origin[7:].to_owned()
    } else {
      ""
    }
    if (
        origin != "app" &&
        (
          authority.is_empty() ||
          authority.contains("/") ||
          authority.contains("?") ||
          authority.contains("#")
        )
      ) ||
      origin.contains("\u0000") {
      raise invalid_argument("bridge source_origin is invalid")
    }
    if origins.length() >= 32 {
      raise invalid_argument("bridge grants array is too large")
    }
    if origins.contains(origin) {
      raise invalid_argument("bridge config contains duplicate source origins")
    }
    origins.push(origin)
    validate_bridge_names(grant.ops, "bridge op name")
    let namespaces : Array[String] = []
    for extension in grant.extensions {
      if !bridge_name_valid(extension.js_namespace) ||
        namespaces.length() >= 256 {
        raise invalid_argument("bridge extension is invalid")
      }
      if namespaces.contains(extension.js_namespace) {
        raise invalid_argument("bridge extension namespace is duplicated")
      }
      namespaces.push(extension.js_namespace)
      validate_bridge_names(extension.apis, "bridge extension API")
    }
    for index, unit in grant.initialization_units {
      if !bridge_name_valid(unit.owner) ||
        !bridge_name_valid(unit.name) ||
        unit.source.contains("\u0000") ||
        index >= 256 {
        raise invalid_argument("bridge initialization unit is invalid")
      }
    }
  }
}

///|
fn ascii_lower(value : String) -> String {
  let result = StringBuilder()
  for c in value {
    result.write_char(c.to_ascii_lowercase())
  }
  result.to_string()
}

///|
fn validate_web_request_config(
  prefixes : Array[String],
  redirects : Array[(String, String)],
  headers : Array[(String, String, String)],
) -> Unit raise NativeError {
  let seen : Array[String] = []
  for prefix in prefixes {
    if prefix.is_empty() || prefix.contains("\u0000") {
      raise invalid_argument("web request URL prefix must not be empty")
    }
    if seen.length() >= 128 {
      raise invalid_argument("web request cancellation prefix limit exceeded")
    }
    if seen.contains(prefix) {
      raise invalid_argument("web request URL prefix is duplicated")
    }
    seen.push(prefix)
  }
  seen.clear()
  for entry in redirects {
    let (prefix, target) = entry
    if prefix.is_empty() ||
      target.is_empty() ||
      prefix.contains("\u0000") ||
      target.contains("\u0000") {
      raise invalid_argument("web request redirect values must not be empty")
    }
    if seen.length() >= 128 {
      raise invalid_argument("web request redirect prefix limit exceeded")
    }
    if seen.contains(prefix) {
      raise invalid_argument("web request redirect prefix is duplicated")
    }
    seen.push(prefix)
  }
  let header_keys : Array[(String, String)] = []
  for entry in headers {
    let (prefix, name, value) = entry
    if prefix.is_empty() ||
      name.is_empty() ||
      prefix.contains("\u0000") ||
      name.contains("\u0000") ||
      value.contains("\u0000") {
      raise invalid_argument("web request header values are invalid")
    }
    let key = (prefix, ascii_lower(name))
    if header_keys.contains(key) {
      raise invalid_argument("web request header rule is duplicated")
    }
    header_keys.push(key)
  }
}

///|
fn parse_color_argb(text : String, context : String) -> UInt raise NativeError {
  if (text.length() != 7 && text.length() != 9) || !text.has_prefix("#") {
    raise invalid_argument(context + " must be #RRGGBB or #AARRGGBB")
  }
  let mut color : UInt = if text.length() == 7 { 0xff } else { 0 }
  for i = 1; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    let digit = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 65 && c <= 70 {
      c - 55
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      raise invalid_argument(context + " must be #RRGGBB or #AARRGGBB")
    }
    color = (color << 4) | digit.reinterpret_as_uint()
  }
  color
}

///|
fn validate_menu(menu : Menu, submenu : Bool) -> Unit raise NativeError {
  let label = menu.label.unwrap_or("")
  if label.is_empty() || label.contains("\u0000") {
    raise invalid_argument(
      if submenu {
        "menu submenu requires a label"
      } else {
        "menu label and index output are required"
      },
    )
  }
  for item in menu.items.unwrap_or([]) {
    match item.kind {
      Command => {
        let id = item.id.unwrap_or("")
        let label = item.label.unwrap_or("")
        if id.is_empty() ||
          label.is_empty() ||
          id.contains("\u0000") ||
          label.contains("\u0000") {
          raise invalid_argument("menu command requires id and label")
        }
      }
      Role =>
        if item.role is None {
          raise invalid_argument("menu role is unsupported")
        }
      Submenu =>
        match item.submenu {
          Some(child) => validate_menu(child, true)
          None => raise invalid_argument("submenu item requires a submenu")
        }
      Separator => ()
    }
  }
}
