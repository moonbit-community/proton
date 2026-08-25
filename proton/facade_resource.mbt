///|
async fn resolve_resource_request(
  document : ResourceDocument?,
  asset_root : String?,
  url : String,
) -> ResourceResponse {
  match document {
    Some(document) if document.url == url =>
      return resource_response(200, "text/html", document.content)
    _ => ()
  }
  guard url.has_prefix(asset_base_url()) else {
    return resource_text_response(404, "Not Found")
  }
  guard asset_root is Some(root) else {
    return resource_text_response(404, "Not Found")
  }
  guard resource_url_path(url) is Some(relative_path) else {
    return resource_text_response(400, "Invalid resource path")
  }
  let native_relative = if @mbpath.sep == '\\' {
    relative_path.replace_all(old="/", new="\\")
  } else {
    relative_path
  }
  let candidate = @mbpath.Path(root).join(native_relative).to_string()
  let canonical = @async_fs.realpath(candidate) catch {
    _ => return resource_text_response(404, "Not Found")
  }
  guard resource_path_is_under_root(canonical, root) else {
    return resource_text_response(404, "Not Found")
  }
  let data = @async_fs.read_file(canonical) catch {
    _ => return resource_text_response(404, "Not Found")
  }
  resource_response(200, resource_mime_type(canonical), data.binary())
}

///|
fn resource_document_url_is_supported(url : String) -> Bool {
  url.has_prefix("proton://") || url.has_prefix(asset_base_url())
}

///|
fn resource_response(
  status : Int,
  mime_type : String,
  body : Bytes,
) -> ResourceResponse {
  { status, mime_type, body }
}

///|
fn resource_text_response(status : Int, body : String) -> ResourceResponse {
  resource_response(status, "text/plain", @utf8.encode(body))
}

///|
fn resource_url_path(url : String) -> String? {
  guard url.has_prefix(asset_base_url()) else { return None }
  let suffix = @utf8.encode(url[asset_base_url().length():])
  let mut end = suffix.length()
  for index = 0; index < suffix.length(); index = index + 1 {
    if suffix[index] == b'?' || suffix[index] == b'#' {
      end = index
      break
    }
  }
  guard end > 0 else { return None }
  resource_percent_decode_path(suffix[:end])
}

///|
fn resource_percent_decode_path(encoded : BytesView) -> String? {
  let decoded : Array[Byte] = []
  let mut index = 0
  while index < encoded.length() {
    let byte = encoded[index]
    if byte == b'%' {
      guard index + 2 < encoded.length() else { return None }
      guard resource_hex_value(encoded[index + 1]) is Some(high) else {
        return None
      }
      guard resource_hex_value(encoded[index + 2]) is Some(low) else {
        return None
      }
      let value = (high * 16 + low).to_byte()
      guard value != b'\x00' else { return None }
      decoded.push(value)
      index = index + 3
    } else {
      guard byte != b'\x00' else { return None }
      decoded.push(byte)
      index = index + 1
    }
  }
  guard decoded.length() > 0 else { return None }
  let path = @utf8.decode(Bytes::from_array(decoded[:])[:]) catch {
    _ => return None
  }
  guard path[0] != '/' && path[0] != '\\' else { return None }
  if @mbpath.sep == '\\' && path.contains(":") {
    return None
  }
  guard !resource_path_has_parent_segment(path) else { return None }
  Some(path.replace_all(old="\\", new="/"))
}

///|
fn resource_hex_value(byte : Byte) -> Int? {
  if byte >= b'0' && byte <= b'9' {
    Some(byte.to_int() - b'0'.to_int())
  } else if byte >= b'a' && byte <= b'f' {
    Some(byte.to_int() - b'a'.to_int() + 10)
  } else if byte >= b'A' && byte <= b'F' {
    Some(byte.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn resource_path_has_parent_segment(path : String) -> Bool {
  let mut segment = StringBuilder()
  for character in path {
    if character == '/' || character == '\\' {
      if segment.to_string() == ".." {
        return true
      }
      segment = StringBuilder()
    } else {
      segment.write_char(character)
    }
  }
  segment.to_string() == ".."
}

///|
fn resource_path_is_under_root(path : String, root : String) -> Bool {
  let separator = @mbpath.sep
  let separator_unit = separator.to_int().to_uint16()
  let mut normalized_root = root
  while normalized_root.length() > 1 &&
        normalized_root[normalized_root.length() - 1] == separator_unit {
    normalized_root = normalized_root[:normalized_root.length() - 1].to_owned()
  }
  let compared_path = if separator == '\\' { path.to_lower() } else { path }
  let compared_root = if separator == '\\' {
    normalized_root.to_lower()
  } else {
    normalized_root
  }
  if compared_root == separator.to_string() {
    return compared_path.has_prefix(compared_root)
  }
  compared_path == compared_root ||
  (
    compared_path.has_prefix(compared_root) &&
    compared_path.length() > compared_root.length() &&
    compared_path[compared_root.length()] == separator_unit
  )
}

///|
fn resource_mime_type(path : String) -> String {
  let lower = path.to_lower()
  if lower.has_suffix(".html") || lower.has_suffix(".htm") {
    "text/html"
  } else if lower.has_suffix(".css") {
    "text/css"
  } else if lower.has_suffix(".js") || lower.has_suffix(".mjs") {
    "text/javascript"
  } else if lower.has_suffix(".json") {
    "application/json"
  } else if lower.has_suffix(".svg") {
    "image/svg+xml"
  } else if lower.has_suffix(".png") {
    "image/png"
  } else if lower.has_suffix(".jpg") || lower.has_suffix(".jpeg") {
    "image/jpeg"
  } else if lower.has_suffix(".gif") {
    "image/gif"
  } else if lower.has_suffix(".webp") {
    "image/webp"
  } else if lower.has_suffix(".ico") {
    "image/x-icon"
  } else if lower.has_suffix(".txt") {
    "text/plain"
  } else if lower.has_suffix(".woff") {
    "font/woff"
  } else if lower.has_suffix(".woff2") {
    "font/woff2"
  } else if lower.has_suffix(".ttf") {
    "font/ttf"
  } else if lower.has_suffix(".otf") {
    "font/otf"
  } else {
    "application/octet-stream"
  }
}
