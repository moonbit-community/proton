///|
fn build_command_host(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  base_dir : String?,
) -> Result[CommandHostRuntime?, String] {
  let host = @core.AppCommandHost::new()
  let destroy_hooks : Array[() -> Unit] = []
  let mut has_commands = false
  let ordered_ids = match
    enabled_command_extension_order(manifest, command_extensions) {
    Err(error) => {
      close_command_host_runtime(host, destroy_hooks)
      return Err(error)
    }
    Ok(ids) => ids
  }
  for id in ordered_ids {
    let spec = command_extensions[id]
    let setting = manifest.extension_setting(id).unwrap()
    let context = @proton_command.AppCommandExtensionContext::new(
      host,
      id,
      spec.js_namespace(),
      options=setting.options(),
      base_dir~,
    )
    match spec.register(context) {
      Err(error) => {
        close_command_host_runtime(host, destroy_hooks)
        return Err(error)
      }
      Ok(_) => {
        has_commands = true
        destroy_hooks.push(fn() { spec.destroy(context) })
      }
    }
  }
  if has_commands {
    host.seal_registrations()
    Ok(Some(CommandHostRuntime::{ host, destroy_hooks, closed: false }))
  } else {
    close_command_host_runtime(host, destroy_hooks)
    Ok(None)
  }
}

///|
fn close_command_host_runtime(
  host : @core.AppCommandHost,
  destroy_hooks : Array[() -> Unit],
) -> Unit {
  let hook_count = destroy_hooks.length()
  for index in 0..<hook_count {
    destroy_hooks[hook_count - index - 1]()
  }
  host.close()
}

///|
fn enabled_command_extension_order(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[Array[String], String] {
  let visit_state : Map[String, Int] = Map([])
  let ordered : Array[String] = []
  for id, _spec in command_extensions {
    match manifest.extension_setting(id) {
      Some(setting) if setting.is_enabled() =>
        match
          visit_enabled_command_extension(
            id,
            None,
            manifest,
            command_extensions,
            visit_state,
            ordered,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None => ()
      _ => ()
    }
  }
  Ok(ordered)
}

///|
fn visit_enabled_command_extension(
  id : String,
  requested_by : String?,
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  visit_state : Map[String, Int],
  ordered : Array[String],
) -> Result[Unit, String] {
  match visit_state.get(id) {
    Some(2) => return Ok(())
    Some(1) =>
      return Err("command extension dependency cycle detected at: " + id)
    _ => ()
  }
  let spec = match
    require_enabled_command_extension(
      id, requested_by, manifest, command_extensions,
    ) {
    Err(error) => return Err(error)
    Ok(spec) => spec
  }
  visit_state[id] = 1
  for dependency in spec.dependencies() {
    match
      visit_enabled_command_extension(
        dependency,
        Some(id),
        manifest,
        command_extensions,
        visit_state,
        ordered,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  visit_state[id] = 2
  ordered.push(id)
  Ok(())
}

///|
fn require_enabled_command_extension(
  id : String,
  requested_by : String?,
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[@proton_command.AppCommandExtensionSpec, String] {
  match manifest.extension_setting(id) {
    Some(setting) if setting.is_enabled() => ()
    Some(_) =>
      return Err(
        command_extension_dependency_error(id, requested_by, "disabled"),
      )
    None =>
      return Err(
        command_extension_dependency_error(id, requested_by, "missing"),
      )
  }
  match command_extensions.get(id) {
    Some(spec) => Ok(spec)
    None =>
      Err(command_extension_dependency_error(id, requested_by, "unregistered"))
  }
}

///|
fn command_extension_dependency_error(
  id : String,
  requested_by : String?,
  state : String,
) -> String {
  match requested_by {
    Some(parent) =>
      "command extension " + parent + " requires " + state + " dependency " + id
    None => "enabled command extension is " + state + ": " + id
  }
}

///|
fn build_bridge_frontend_config(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[BridgeFrontendConfig, String] {
  let extensions : Array[@native.BridgeExtensionConfig] = []
  let scripts : Array[String] = []
  let ordered_ids = match
    enabled_command_extension_order(manifest, command_extensions) {
    Err(error) => return Err(error)
    Ok(ids) => ids
  }
  for id in ordered_ids {
    let spec = command_extensions[id]
    let js_namespace = spec.js_namespace()
    if command_proxy_name_is_invalid(js_namespace) {
      return Err(
        "command extension namespace cannot be exposed to JavaScript: " +
        js_namespace,
      )
    }
    let apis : Array[String] = []
    for api in spec.apis() {
      let api_name = api.api_name()
      if command_proxy_name_is_invalid(api_name) {
        return Err(
          "command extension API cannot be exposed to JavaScript: " +
          js_namespace +
          "." +
          api_name,
        )
      }
      apis.push(api_name)
    }
    extensions.push(@native.BridgeExtensionConfig::new(js_namespace, apis~))
    for script in spec.scripts() {
      scripts.push(script)
    }
  }
  Ok(BridgeFrontendConfig::{
    extensions,
    initialization_script: if scripts.length() == 0 {
      None
    } else {
      Some(scripts.join("\n"))
    },
  })
}

///|
fn command_proxy_name_is_invalid(name : String) -> Bool {
  name.trim().to_owned() == "" ||
  name == "core" ||
  name == "events" ||
  @proton_command.app_command_js_property_is_reserved(name)
}

///|
fn install_extension_event_sender(
  window : @native.Window,
  host : @core.AppCommandHost,
) -> Unit {
  host.set_event_sender(extension_event_sender(window, None))
}

///|
fn forward_menu_command(
  window : @native.Window,
  command_id : String,
  focused_window : Int64?,
) -> Unit {
  let fields : Map[String, Json] = { "command_id": Json::string(command_id) }
  match focused_window {
    Some(window) => fields["window"] = Json::string(window.to_string())
    None => ()
  }
  ignore(
    window.emit_bridge_event_json(
      bridge_event_json(
        "frontend",
        "menu.command",
        Json::object(fields),
        None,
        None,
      ),
    ),
  )
}

///|
fn bridge_event_json(
  kind : String,
  name : String,
  payload : Json,
  extension : String?,
  page_instance : String?,
) -> String {
  let fields : Map[String, Json] = {
    "abi_version": Json::number(1),
    "kind": Json::string(kind),
    "name": Json::string(name),
    "payload": payload,
  }
  match extension {
    Some(value) => fields["extension"] = Json::string(value)
    None => ()
  }
  match page_instance {
    Some(value) => fields["page_instance"] = Json::string(value)
    None => ()
  }
  Json::object(fields).stringify()
}

///|
fn extension_event_sender(
  window : @native.Window,
  page_instance : String?,
) -> async (@ipc.IpcExtensionEvent) -> Unit {
  async fn(event) {
    ignore(
      window.emit_bridge_event_json(
        bridge_event_json(
          "extension",
          event.event_name,
          event.payload,
          Some(event.extension_namespace),
          page_instance,
        ),
      ),
    )
    @async.sleep(0)
  }
}

///|
async fn dispatch_bridge_request(
  window : @native.Window,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
  policy : BridgePagePolicy,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  let request_context = @core.AppCommandRequestContext::new(request.window())
  let response = match
    @async.with_timeout_opt(policy.request_timeout_ms, () => {
      host.dispatch_ipc_with_context_and_event_sender(
        request_context,
        @ipc.IpcOpRequest::new(
          request_id.to_string(),
          request.op(),
          request.payload(),
        ),
        Some(extension_event_sender(window, request.page_instance())),
      )
    }) {
    Some(response) => response
    None =>
      return @native.BridgeResponse::Err(
        request_id~,
        code="request_timeout",
        message="bridge request timed out",
      )
  }
  if response.is_ok() {
    @native.BridgeResponse::Ok(request_id~, payload=response.body)
  } else {
    let message = match response.body {
      String(text) => text
      _ => response.body.stringify()
    }
    @native.BridgeResponse::Err(request_id~, code="op_failed", message~)
  }
}

///|
fn default_bridge_page_policy() -> BridgePagePolicy {
  BridgePagePolicy::{ dev_origin: None, request_timeout_ms: 30000 }
}

///|
fn bridge_page_policy_for_manifest(
  manifest : @manifest.AppManifest,
) -> Result[BridgePagePolicy, String] {
  if !proton_dev_mode_enabled() {
    return Ok(default_bridge_page_policy())
  }
  match manifest.entry {
    @manifest.AppEntry::Url(url) =>
      url_origin(url).map(fn(origin) {
        BridgePagePolicy::{
          dev_origin: Some(origin),
          request_timeout_ms: 30000,
        }
      })
    _ => Ok(default_bridge_page_policy())
  }
}

///|
fn url_origin(url : String) -> Result[String, String] {
  let (scheme_view, rest_view) = match url.split_once("://") {
    Some(parts) => parts
    None =>
      return Err("dev bridge URL must include http:// or https://: " + url)
  }
  let scheme = scheme_view.to_owned().to_lower()
  if scheme != "http" && scheme != "https" {
    return Err("dev bridge URL must use http or https: " + url)
  }
  let rest = rest_view.to_owned()
  if rest == "" {
    return Err("dev bridge URL is missing host: " + url)
  }
  let mut end = rest.length()
  for delimiter in ["/", "?", "#"] {
    match rest.find(delimiter) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  if end == 0 {
    return Err("dev bridge URL is missing host: " + url)
  }
  let authority = rest.unsafe_substring(start=0, end~).to_string()
  if !dev_origin_authority_is_valid(authority) {
    return Err("dev bridge URL has invalid origin: " + url)
  }
  canonical_dev_origin_authority(authority, scheme).map(fn(authority) {
    scheme + "://" + authority
  })
}

///|
fn dev_origin_authority_is_valid(authority : String) -> Bool {
  if authority == "" || authority.contains("@") {
    return false
  }
  for ch in authority {
    let code = ch.to_int()
    if code <= 0x20 ||
      code >= 0x7f ||
      ch == '/' ||
      ch == '?' ||
      ch == '#' ||
      ch == '"' ||
      ch == '\\' {
      return false
    }
  }
  true
}

///|
fn canonical_dev_origin_authority(
  authority : String,
  scheme : String,
) -> Result[String, String] {
  if authority.has_prefix("[") {
    let (host_part, suffix) = match authority.split_once("]") {
      Some(parts) => parts
      None => return Err("dev bridge URL has invalid IPv6 origin: " + authority)
    }
    let host_text = host_part.to_owned()
    let host = host_text
      .unsafe_substring(start=1, end=host_text.length())
      .to_string()
    if host == "" {
      return Err("dev bridge URL host must not be empty")
    }
    if suffix != "" && !suffix.has_prefix(":") {
      return Err("dev bridge URL has invalid IPv6 origin: " + authority)
    }
    canonical_dev_origin_port_suffix(suffix.to_owned(), scheme).map(fn(port) {
      "[" + host.to_lower() + "]" + port
    })
  } else {
    let first_colon = authority.find(":")
    let last_colon = authority.rev_find(":")
    if first_colon != last_colon {
      return Err("dev bridge IPv6 origins must use brackets: " + authority)
    }
    match first_colon {
      None => Ok(authority.to_lower())
      Some(index) => {
        let host = authority.unsafe_substring(start=0, end=index).to_string()
        let port = authority
          .unsafe_substring(start=index + 1, end=authority.length())
          .to_string()
        if host == "" {
          return Err("dev bridge URL host must not be empty")
        }
        if port == "" {
          return Err("dev bridge URL port must not be empty")
        }
        canonical_dev_origin_port_suffix(port, scheme).map(fn(port) {
          host.to_lower() + port
        })
      }
    }
  }
}

///|
fn canonical_dev_origin_port_suffix(
  port : String,
  scheme : String,
) -> Result[String, String] {
  if port == "" {
    return Ok("")
  }
  let text = if port.has_prefix(":") { port[1:].to_owned() } else { port }
  if text == "" {
    return Err("dev bridge URL port must not be empty")
  }
  let value = @string.parse_int(text[:]) catch {
    _ => return Err("dev bridge URL port must be an integer: " + text)
  }
  if value <= 0 || value > 65535 {
    return Err("dev bridge URL port is out of range: " + text)
  }
  let default_port = if scheme == "http" { 80 } else { 443 }
  if value == default_port {
    Ok("")
  } else {
    Ok(":" + value.to_string())
  }
}

///|
fn bridge_page_policy_dev_origins(policy : BridgePagePolicy) -> Array[String] {
  match policy.dev_origin {
    Some(origin) => [origin]
    None => []
  }
}
