///|
/// The browser origin and socket endpoint of an application or development URL.
pub struct HttpUrl {
  origin : String
  host : String
  port : Int32
}

///|
/// Invalid input for an HTTP(S) application or development URL.
pub(all) suberror HttpUrlError {
  MissingScheme
  UnsupportedScheme
  MissingHost
  InvalidOrigin(reason~ : String)
  EmptyPort
  ZeroPort
}

///|
/// Parse an absolute HTTP(S) URL using browser host and port normalization.
pub fn parse_http_url(url : String) -> HttpUrl raise HttpUrlError {
  let (scheme, rest) = match url.split_once("://") {
    Some(parts) => parts
    None => raise MissingScheme
  }
  let default_port = match scheme.to_owned().to_lower() {
    "http" => 80
    "https" => 443
    _ => raise UnsupportedScheme
  }
  // Check Proton's input restrictions before the browser parser can normalize
  // away credentials, whitespace, backslashes or an empty port.
  let mut end = rest.length()
  for delimiter in ["/", "?", "#"] {
    match rest.find(delimiter) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  let authority = rest[:end]
  if authority.is_empty() ||
    authority.has_prefix(":") ||
    authority == "[]" ||
    authority.has_prefix("[]:") {
    raise MissingHost
  }
  for ch in authority {
    let code = ch.to_int()
    if code <= 0x20 || code >= 0x7f || ch is ('@' | '"' | '\\') {
      raise InvalidOrigin(reason="URL has an invalid origin")
    }
  }
  if authority.has_suffix(":") {
    raise EmptyPort
  }
  let parsed = @url.Url::parse(url[:]) catch {
    _ => {
      let reason = if authority.has_prefix("[") {
        "URL has an invalid IPv6 origin"
      } else {
        "URL has an invalid origin"
      }
      raise InvalidOrigin(reason~)
    }
  }
  let port = match parsed.port {
    None => default_port
    Some(0) => raise ZeroPort
    Some(value) => value.to_int()
  }
  let host = match parsed.host {
    Some(IPv6(address)) => address.to_string()
    _ => parsed.hostname()
  }
  { origin: parsed.origin(), host, port, }
}
