///|
/// Errors raised while normalizing a remote debugging target or reading Chrome's
/// HTTP discovery endpoints.
///
/// Use `diagnostic` when presenting the error in CLI output or test logs,
/// because it gives callers a stable `kind`, `path`, and optional metadata.
///
/// Variants map to the discovery stage that failed:
///
/// - `InvalidTarget`: the user-supplied target string or derived URL could not
///   be parsed as a supported CDP target.
/// - `HttpStatus`: Chrome's discovery endpoint responded with a non-2xx status.
/// - `MissingWebSocketDebuggerUrl`: `/json/version` did not include the
///   browser-level WebSocket URL.
/// - `MissingTargetWebSocketDebuggerUrl`: a selected `/json/list` target did
///   not include a page-level WebSocket URL.
/// - `NoMatchingTarget`: `/json/list` was valid but no target matched the
///   supplied filters.
/// - `InvalidVersionResponse`: discovery JSON was present but not in the shape
///   required by this library.
pub(all) suberror DiscoveryError {
  InvalidTarget(String)
  HttpStatus(Int, String)
  MissingWebSocketDebuggerUrl
  MissingTargetWebSocketDebuggerUrl(String)
  NoMatchingTarget(String)
  InvalidVersionResponse
} derive(Eq, ToJson, Debug)

///|
/// Structured details for a `DiscoveryError`.
///
/// The `path` field points at the target string, HTTP request, or JSON field
/// that failed, while optional fields are populated only for matching error
/// variants.
pub(all) struct DiscoveryErrorDiagnostic {
  kind : String
  target : String?
  http_status : Int?
  reason : String?
  target_id : String?
  selector : String?
  path : String
  message : String
} derive(Eq, ToJson, Debug)

///|
/// Convert a discovery error into stable structured diagnostic data.
///
/// # Example
/// ```mbt nocheck
/// let diagnostic = DiscoveryError::InvalidTarget("chrome").diagnostic()
/// assert_eq(diagnostic.kind, "invalid_target")
/// ```
pub fn DiscoveryError::diagnostic(
  self : DiscoveryError,
) -> DiscoveryErrorDiagnostic {
  {
    kind: self.kind(),
    target: self.target(),
    http_status: self.http_status(),
    reason: self.reason(),
    target_id: self.target_id(),
    selector: self.selector(),
    path: self.path(),
    message: self.message(),
  }
}

///|
/// Return the stable machine-readable error kind.
pub fn DiscoveryError::kind(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(_) => "invalid_target"
    HttpStatus(_, _) => "http_status"
    MissingWebSocketDebuggerUrl => "missing_websocket_debugger_url"
    MissingTargetWebSocketDebuggerUrl(_) =>
      "missing_target_websocket_debugger_url"
    NoMatchingTarget(_) => "no_matching_target"
    InvalidVersionResponse => "invalid_version_response"
  }
}

///|
/// Return a JSON-style path identifying where discovery failed.
pub fn DiscoveryError::path(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(_) => "target"
    HttpStatus(_, _) => "discovery.http"
    MissingWebSocketDebuggerUrl => "json.version.webSocketDebuggerUrl"
    MissingTargetWebSocketDebuggerUrl(target_id) =>
      "json.list[\{target_id}].webSocketDebuggerUrl"
    NoMatchingTarget(_) => "json.list"
    InvalidVersionResponse => "json.version"
  }
}

///|
/// Return a human-readable error message suitable for CLI output.
pub fn DiscoveryError::message(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(target) => "invalid CDP target: \{target}"
    HttpStatus(code, reason) =>
      "remote debugging endpoint returned HTTP \{code} \{reason}"
    MissingWebSocketDebuggerUrl =>
      "remote debugging /json/version response is missing webSocketDebuggerUrl"
    MissingTargetWebSocketDebuggerUrl(target_id) =>
      "target \{target_id} is missing webSocketDebuggerUrl"
    NoMatchingTarget(selector) =>
      "no remote debugging target matched \{selector}"
    InvalidVersionResponse =>
      "remote debugging /json/version response has invalid shape"
  }
}

///|
/// Return the invalid target string when the error came from target parsing.
pub fn DiscoveryError::target(self : DiscoveryError) -> String? {
  match self {
    InvalidTarget(target) => Some(target)
    _ => None
  }
}

///|
/// Return the HTTP status code when a discovery request failed.
pub fn DiscoveryError::http_status(self : DiscoveryError) -> Int? {
  match self {
    HttpStatus(code, _) => Some(code)
    _ => None
  }
}

///|
/// Return the HTTP reason phrase when a discovery request failed.
pub fn DiscoveryError::reason(self : DiscoveryError) -> String? {
  match self {
    HttpStatus(_, reason) => Some(reason)
    _ => None
  }
}

///|
/// Return the target id whose `webSocketDebuggerUrl` was missing.
pub fn DiscoveryError::target_id(self : DiscoveryError) -> String? {
  match self {
    MissingTargetWebSocketDebuggerUrl(target_id) => Some(target_id)
    _ => None
  }
}

///|
/// Return the selector that failed to match any discovered target.
pub fn DiscoveryError::selector(self : DiscoveryError) -> String? {
  match self {
    NoMatchingTarget(selector) => Some(selector)
    _ => None
  }
}

///|
/// A CDP connection target accepted by discovery helpers.
///
/// `WebSocket` targets are already resolved and can be connected directly.
/// `Http` targets point at a Chrome remote debugging base URL and are resolved
/// through `/json/version` or `/json/list`.
///
/// `parse_cdp_target` is the preferred way to construct this enum from user
/// input. It normalizes ports and `host:port` strings into `Http` targets and
/// strips one trailing slash from HTTP base URLs.
pub(all) enum CdpTarget {
  WebSocket(String)
  Http(String)
} derive(Eq, ToJson, Debug)

///|
/// Metadata returned by Chrome's `/json/version` discovery endpoint.
///
/// `web_socket_debugger_url` is normalized for local `127.0.0.1` endpoints so
/// callers can connect to the same host they used for discovery. `raw` retains
/// the original JSON object for fields not modeled by this struct.
///
/// `browser` and `protocol_version` are required by Chrome's response and are
/// therefore non-optional. `user_agent`, `v8_version`, and `webkit_version`
/// are optional because non-Chrome-compatible endpoints may omit them.
pub(all) struct CdpVersionInfo {
  browser : String
  protocol_version : String
  user_agent : String?
  v8_version : String?
  webkit_version : String?
  web_socket_debugger_url : String
  raw : Json
} derive(Eq, ToJson, Debug)

///|
/// A single target returned by Chrome's `/json/list` endpoint.
///
/// Page selection helpers match against `target_id`, `target_type`, `url`, and
/// `title`; `raw` preserves the full target object for consumers that need
/// Chrome-specific fields.
///
/// Common `target_type` values include `page`, `iframe`, `service_worker`, and
/// `shared_worker`. Page WebSocket URLs are optional in Chrome's schema, so
/// callers that require a direct page socket should handle
/// `MissingTargetWebSocketDebuggerUrl`.
pub(all) struct CdpDiscoveredTarget {
  target_id : String
  target_type : String
  title : String
  url : String
  description : String
  devtools_frontend_url : String?
  web_socket_debugger_url : String?
  raw : Json
} derive(Eq, ToJson, Debug)

///|
/// Parse a user-supplied target string into a CDP target.
///
/// Supported forms are full WebSocket URLs (`ws://` or `wss://`), HTTP(S)
/// discovery base URLs, numeric ports, and `host:port` pairs. Numeric ports are
/// normalized to `http://127.0.0.1:<port>`.
///
/// # Example
/// ```mbt nocheck
/// let target = parse_cdp_target("9222")
/// assert_eq(target, CdpTarget::Http("http://127.0.0.1:9222"))
/// ```
pub fn parse_cdp_target(raw : String) -> CdpTarget raise DiscoveryError {
  let target = raw.trim().to_owned()
  if target == "" {
    raise InvalidTarget(raw)
  }
  if target.has_prefix("ws://") || target.has_prefix("wss://") {
    WebSocket(target)
  } else if target.has_prefix("http://") || target.has_prefix("https://") {
    Http(strip_trailing_slash(target))
  } else if target_is_port(target) {
    Http("http://127.0.0.1:\{target}")
  } else if target_is_host_port(target) {
    Http("http://\{target}")
  } else {
    raise InvalidTarget(raw)
  }
}

///|
/// Resolve a target to the browser-level CDP WebSocket URL.
///
/// WebSocket targets are returned unchanged. HTTP targets are queried through
/// `/json/version` and must include a `webSocketDebuggerUrl` field.
///
/// # Example
/// ```mbt nocheck
/// async test {
///   let url = discover_web_socket_url(CdpTarget::Http("http://127.0.0.1:9222"))
///   assert_true(url.has_prefix("ws://"))
/// }
/// ```
pub async fn discover_web_socket_url(target : CdpTarget) -> String {
  if target is WebSocket(url) {
    return url
  }
  let base_url = discovery_base_url(target)
  normalize_discovered_web_socket_url(
    base_url,
    web_socket_url_from_version_json(
      fetch_discovery_json(base_url, "/json/version"),
    ),
  )
}

///|
/// Resolve a target to the browser-level WebSocket URL.
///
/// This is an explicit browser-target alias for `discover_web_socket_url`, used
/// by callers that want their target choice to be visible at the call site.
pub async fn discover_browser_web_socket_url(target : CdpTarget) -> String {
  discover_web_socket_url(target)
}

///|
/// Resolve a target to a page-level CDP WebSocket URL.
///
/// If `target` is already a page WebSocket URL and no filters are provided, it
/// is returned directly. Otherwise the function fetches `/json/list` and
/// selects the first page matching the optional `target_id`, `url`, and `title`
/// filters.
///
/// # Example
/// ```mbt nocheck
/// async test {
///   let page_url = discover_page_web_socket_url(
///     CdpTarget::Http("http://127.0.0.1:9222"),
///   )
///   assert_true(page_url.contains("/devtools/page/"))
/// }
/// ```
pub async fn discover_page_web_socket_url(
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
) -> String {
  match target {
    WebSocket(web_socket_url) =>
      if target_id is None &&
        url is None &&
        title is None &&
        is_page_web_socket_url(web_socket_url) {
        return web_socket_url
      }
    _ => ()
  }
  let selected = select_discovered_page_target(
    discover_targets(target),
    target_id?,
    url?,
    title?,
  )
  match selected.web_socket_debugger_url {
    Some(web_socket_url) => web_socket_url
    None => raise MissingTargetWebSocketDebuggerUrl(selected.target_id)
  }
}

///|
/// Fetch and parse Chrome's `/json/version` discovery response.
///
/// The target may be HTTP or WebSocket. WebSocket targets are converted back to
/// their HTTP discovery base URL before fetching `/json/version`.
pub async fn discover_version(target : CdpTarget) -> CdpVersionInfo {
  let base_url = discovery_base_url(target)
  parse_version_info(fetch_discovery_json(base_url, "/json/version"), base_url)
}

///|
/// Fetch and parse Chrome's `/json/list` target list.
///
/// The returned array preserves Chrome's target order. Selection helpers use
/// that order when more than one target matches the same filters.
pub async fn discover_targets(target : CdpTarget) -> Array[CdpDiscoveredTarget] {
  let base_url = discovery_base_url(target)
  match fetch_discovery_json(base_url, "/json/list") {
    Array(items) => items.map(item => parse_discovered_target(item, base_url))
    _ => raise InvalidTarget("/json/list")
  }
}

///|
/// Select the first discovered page target matching the optional filters.
///
/// All provided filters must match exactly. When no page target matches, the
/// function raises `DiscoveryError::NoMatchingTarget`.
///
/// This helper is intentionally exact-match only. If callers need substring or
/// predicate matching, fetch `discover_targets` and filter the returned array
/// directly before connecting.
pub fn select_discovered_page_target(
  targets : Array[CdpDiscoveredTarget],
  target_id? : String,
  url? : String,
  title? : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  select_discovered_target(
    targets,
    target_id?,
    target_type="page",
    url?,
    title?,
  )
}

///|
/// Select the first discovered target matching the optional filters.
///
/// Use this lower-level selector when matching non-page targets such as workers
/// or service workers. For regular page automation, prefer
/// `select_discovered_page_target`.
pub fn select_discovered_target(
  targets : Array[CdpDiscoveredTarget],
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  for target in targets {
    if discovered_target_matches(target, target_id?, target_type?, url?, title?) {
      return target
    }
  }
  raise NoMatchingTarget(
    target_selection_description(target_id?, target_type?, url?, title?),
  )
}

///|
/// Fetch Chrome's live `/json/protocol` schema as JSON.
///
/// The returned schema can be compared with the bundled protocol manifest by
/// `protocol_schema_diff`.
/// It can also be passed to `send_remote_schema_command` to reject commands not
/// advertised by the current browser before sending them.
pub async fn discover_protocol(target : CdpTarget) -> Json {
  fetch_discovery_json(discovery_base_url(target), "/json/protocol")
}

///|
/// Extract `webSocketDebuggerUrl` from a `/json/version` response.
///
/// The function validates only the fields needed for endpoint discovery and
/// raises `DiscoveryError` when the response is not an object, the field is not
/// a string, or the field is missing.
pub fn web_socket_url_from_version_json(
  json : Json,
) -> String raise DiscoveryError {
  guard json is Object(fields) else { raise InvalidVersionResponse }
  match fields.get("webSocketDebuggerUrl") {
    Some(String(url)) => url
    Some(_) => raise InvalidVersionResponse
    None => raise MissingWebSocketDebuggerUrl
  }
}

///|
// Parse `/json/version` into public version metadata.
fn parse_version_info(
  json : Json,
  base_url : String,
) -> CdpVersionInfo raise DiscoveryError {
  guard json is Object(fields) else { raise InvalidVersionResponse }
  let web_socket_debugger_url = normalize_discovered_web_socket_url(
    base_url,
    web_socket_url_from_version_json(json),
  )
  {
    browser: discovery_required_string(fields, "Browser"),
    protocol_version: discovery_required_string(fields, "Protocol-Version"),
    user_agent: discovery_optional_string(fields, "User-Agent"),
    v8_version: discovery_optional_string(fields, "V8-Version"),
    webkit_version: discovery_optional_string(fields, "WebKit-Version"),
    web_socket_debugger_url,
    raw: json,
  }
}

///|
// Parse one `/json/list` item into target metadata.
fn parse_discovered_target(
  json : Json,
  base_url : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  guard json is Object(fields) else { raise InvalidTarget("/json/list item") }
  let web_socket_debugger_url = match
    discovery_optional_string(fields, "webSocketDebuggerUrl") {
    Some(url) => Some(normalize_discovered_web_socket_url(base_url, url))
    None => None
  }
  {
    target_id: discovery_required_string(fields, "id"),
    target_type: discovery_required_string(fields, "type"),
    title: discovery_optional_string(fields, "title").unwrap_or(""),
    url: discovery_optional_string(fields, "url").unwrap_or(""),
    description: discovery_optional_string(fields, "description").unwrap_or(""),
    devtools_frontend_url: discovery_optional_string(
      fields, "devtoolsFrontendUrl",
    ),
    web_socket_debugger_url,
    raw: json,
  }
}

///|
// Fetch a JSON discovery endpoint and reject non-2xx HTTP statuses.
async fn fetch_discovery_json(base_url : String, path : String) -> Json {
  let url = "\{strip_trailing_slash(base_url)}\{path}"
  let (response, body) = @http.get(url)
  if response.code < 200 || response.code >= 300 {
    raise HttpStatus(response.code, response.reason)
  }
  body.json()
}

///|
// Convert any accepted target into an HTTP discovery base URL.
fn discovery_base_url(target : CdpTarget) -> String raise DiscoveryError {
  match target {
    Http(base_url) => strip_trailing_slash(base_url)
    WebSocket(url) => {
      let (scheme, rest) = web_socket_url_rest(url)
      let authority = web_socket_authority(rest)
      let http_scheme = if scheme == "wss" { "https" } else { "http" }
      "\{http_scheme}://\{authority}"
    }
  }
}

///|
// Keep localhost-discovered WebSocket URLs aligned with the requested base host.
fn normalize_discovered_web_socket_url(
  base_url : String,
  web_socket_url : String,
) -> String raise DiscoveryError {
  let (_, ws_rest) = web_socket_url_rest(web_socket_url)
  let (ws_authority, ws_path) = split_authority_and_path(ws_rest)
  let base_authority = http_url_authority(base_url)
  if authority_host(base_authority) == "127.0.0.1" &&
    authority_host(ws_authority) == "localhost" {
    replace_web_socket_authority(web_socket_url, base_authority, ws_path)
  } else {
    web_socket_url
  }
}

///|
/// Build a DevTools frontend URL for a page target.
///
/// `browser_web_socket_url` must be the browser-level endpoint returned by
/// `/json/version`, while `target_id` is the page target id from `/json/list`.
/// The returned HTTP(S) URL opens Chrome's built-in DevTools frontend for that
/// target when the debugging browser exposes the standard frontend route.
///
/// # Example
/// ```mbt nocheck
/// let url = devtools_frontend_url(
///   "ws://127.0.0.1:9222/devtools/browser/abc",
///   "page-1",
/// )
/// assert_true(url.contains("/devtools/inspector.html"))
/// ```
pub fn devtools_frontend_url(
  browser_web_socket_url : String,
  target_id : String,
) -> String raise DiscoveryError {
  let (scheme, rest) = web_socket_url_rest(browser_web_socket_url)
  let authority = web_socket_authority(rest)
  let frontend_scheme = if scheme == "wss" { "https" } else { "http" }
  "\{frontend_scheme}://\{authority}/devtools/inspector.html?ws=\{authority}/devtools/page/\{target_id}"
}

///|
// Split a WebSocket URL into scheme and authority/path text.
fn web_socket_url_rest(url : String) -> (String, String) raise DiscoveryError {
  match url.strip_prefix("ws://") {
    Some(rest) => ("ws", rest.to_owned())
    None =>
      match url.strip_prefix("wss://") {
        Some(rest) => ("wss", rest.to_owned())
        None => raise InvalidTarget(url)
      }
  }
}

///|
// Extract the non-empty authority from a WebSocket URL rest segment.
fn web_socket_authority(rest : String) -> String raise DiscoveryError {
  let (authority, _) = split_authority_and_path(rest)
  if authority == "" {
    raise InvalidTarget(rest)
  } else {
    authority
  }
}

///|
// Split an authority/path segment at the first slash.
fn split_authority_and_path(rest : String) -> (String, String) {
  match rest.find("/") {
    Some(index) => (rest[:index].to_owned(), rest[index:].to_owned())
    None => (rest, "")
  }
}

///|
// Extract the authority from an HTTP or HTTPS URL.
fn http_url_authority(url : String) -> String raise DiscoveryError {
  let rest = match url.strip_prefix("http://") {
    Some(rest) => rest
    None =>
      match url.strip_prefix("https://") {
        Some(rest) => rest
        None => raise InvalidTarget(url)
      }
  }
  let (authority, _) = split_authority_and_path(rest.to_owned())
  if authority == "" {
    raise InvalidTarget(url)
  } else {
    authority
  }
}

///|
// Extract and lowercase the host portion of an authority.
fn authority_host(authority : String) -> String {
  let host = if authority.has_prefix("[") {
    match authority.find("]") {
      Some(end) => authority[:end + 1].to_owned()
      None => authority
    }
  } else {
    match authority.find(":") {
      Some(index) => authority[:index].to_owned()
      None => authority
    }
  }
  host.to_lower()
}

///|
// Rebuild a WebSocket URL with a replacement authority.
fn replace_web_socket_authority(
  url : String,
  authority : String,
  path : String,
) -> String raise DiscoveryError {
  let (scheme, _) = web_socket_url_rest(url)
  "\{scheme}://\{authority}\{path}"
}

///|
// Check whether a WebSocket URL points at a page target.
fn is_page_web_socket_url(url : String) -> Bool {
  url.contains("/devtools/page/")
}

///|
// Check all provided target filters against a discovered target.
fn discovered_target_matches(
  target : CdpDiscoveredTarget,
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> Bool {
  optional_target_field_matches(target.target_id, target_id) &&
  optional_target_field_matches(target.target_type, target_type) &&
  optional_target_field_matches(target.url, url) &&
  optional_target_field_matches(target.title, title)
}

///|
// Match a target field when the expected value is optional.
fn optional_target_field_matches(value : String, expected : String?) -> Bool {
  match expected {
    Some(expected) => value == expected
    None => true
  }
}

///|
// Render target filters for a no-match diagnostic.
fn target_selection_description(
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> String {
  let parts : Array[String] = []
  if target_id is Some(target_id) {
    parts.push("id=\{target_id}")
  }
  if target_type is Some(target_type) {
    parts.push("type=\{target_type}")
  }
  if url is Some(url) {
    parts.push("url=\{url}")
  }
  if title is Some(title) {
    parts.push("title=\{title}")
  }
  if parts.length() == 0 {
    "any target"
  } else {
    parts.join(" ")
  }
}

///|
// Read a required string field from discovery JSON.
fn discovery_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise DiscoveryError {
  match fields.get(name) {
    Some(String(value)) => value
    _ => raise InvalidVersionResponse
  }
}

///|
// Read an optional string field from discovery JSON.
fn discovery_optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise DiscoveryError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidVersionResponse
  }
}

///|
// Remove one trailing slash from a URL or path.
fn strip_trailing_slash(value : String) -> String {
  match value.strip_suffix("/") {
    Some(stripped) => stripped.to_owned()
    None => value
  }
}

///|
// Return true when the string is a valid TCP port number.
fn target_is_port(value : String) -> Bool {
  if value == "" {
    return false
  }
  let mut port = 0
  for char in value {
    if !char.is_ascii_digit() {
      return false
    }
    port = port * 10 + (char.to_int() - '0'.to_int())
  }
  port > 0 && port < 65536
}

///|
// Return true when the string looks like `host:port`.
fn target_is_host_port(value : String) -> Bool {
  match value.rev_find(":") {
    Some(index) if index > 0 && index + 1 < value.length() =>
      !value.contains("/") && target_is_port(value[index + 1:].to_owned())
    _ => false
  }
}
