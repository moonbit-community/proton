///|
fn build_command_host(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  base_dir : String?,
) -> CommandHostRuntime? raise AppRunError {
  let host = @core.AppCommandHost::new()
  let destroy_hooks : Array[CommandExtensionDestroyHook] = []
  let mut has_commands = false
  let ordered_ids = enabled_command_extension_order(
    manifest, command_extensions,
  ) catch {
    error => {
      close_command_host_runtime(host, destroy_hooks) catch {
        _ => ()
      }
      raise ConfigurationError(error)
    }
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
    spec.register(context) catch {
      error => {
        close_command_host_runtime(host, destroy_hooks) catch {
          _ => ()
        }
        raise CommandExtensionLifecycleError(
          RegistrationFailed(
            extension_id=id,
            detail=@debug.render(@debug.to_repr(error)),
          ),
        )
      }
    }
    has_commands = true
    destroy_hooks.push(CommandExtensionDestroyHook::{
      extension_id: id,
      callback: fn() raise { spec.destroy(context) },
    })
  }
  if has_commands {
    host.seal_registrations()
    Some(CommandHostRuntime::{ host, destroy_hooks, closed: false })
  } else {
    close_command_host_runtime(host, destroy_hooks)
    None
  }
}

///|
fn close_command_host_runtime(
  host : @core.AppCommandHost,
  destroy_hooks : Array[CommandExtensionDestroyHook],
) -> Unit raise AppRunError {
  let hook_count = destroy_hooks.length()
  for index in 0..<hook_count {
    let hook = destroy_hooks[hook_count - index - 1]
    (hook.callback)() catch {
      error =>
        raise CommandExtensionLifecycleError(
          DestroyFailed(
            extension_id=hook.extension_id,
            detail=@debug.render(@debug.to_repr(error)),
          ),
        )
    }
  }
  host.close()
}

///|
fn enabled_command_extension_order(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Array[String] raise AppConfigurationError {
  let visit_state : Map[String, Int] = Map([])
  let ordered : Array[String] = []
  for id, _spec in command_extensions {
    match manifest.extension_setting(id) {
      Some(setting) if setting.is_enabled() =>
        visit_enabled_command_extension(
          id,
          None,
          manifest,
          command_extensions,
          visit_state,
          ordered,
        )
      None => ()
      _ => ()
    }
  }
  ordered
}

///|
fn visit_enabled_command_extension(
  id : String,
  requested_by : String?,
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  visit_state : Map[String, Int],
  ordered : Array[String],
) -> Unit raise AppConfigurationError {
  match visit_state.get(id) {
    Some(2) => return
    Some(1) => raise ExtensionDependencyCycle(extension_id=id)
    _ => ()
  }
  let spec = require_enabled_command_extension(
    id, requested_by, manifest, command_extensions,
  )
  visit_state[id] = 1
  for dependency in spec.dependencies() {
    visit_enabled_command_extension(
      dependency,
      Some(id),
      manifest,
      command_extensions,
      visit_state,
      ordered,
    )
  }
  visit_state[id] = 2
  ordered.push(id)
}

///|
fn require_enabled_command_extension(
  id : String,
  requested_by : String?,
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> @proton_command.AppCommandExtensionSpec raise AppConfigurationError {
  match manifest.extension_setting(id) {
    Some(setting) if setting.is_enabled() => ()
    Some(_) =>
      raise ExtensionUnavailable(
        extension_id=id,
        requested_by~,
        state="disabled",
      )
    None =>
      raise ExtensionUnavailable(
        extension_id=id,
        requested_by~,
        state="missing",
      )
  }
  match command_extensions.get(id) {
    Some(spec) => spec
    None =>
      raise ExtensionUnavailable(
        extension_id=id,
        requested_by~,
        state="unregistered",
      )
  }
}

///|
fn build_bridge_frontend_config(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> BridgeFrontendConfig raise AppConfigurationError {
  let extensions : Array[@native.BridgeExtensionConfig] = []
  let initialization_units : Array[@native.BridgeInitializationUnit] = []
  let ordered_ids = enabled_command_extension_order(
    manifest, command_extensions,
  )
  for id in ordered_ids {
    let spec = command_extensions[id]
    let js_namespace = spec.js_namespace()
    if command_proxy_name_is_invalid(js_namespace) {
      raise InvalidJavaScriptNamespace(js_namespace~)
    }
    let apis : Array[String] = []
    for api in spec.apis() {
      let api_name = api.api_name()
      if command_proxy_name_is_invalid(api_name) {
        raise InvalidJavaScriptApi(js_namespace~, api_name~)
      }
      apis.push(api_name)
    }
    extensions.push(@native.BridgeExtensionConfig::new(js_namespace, apis~))
    let scripts = spec.scripts()
    for index, script in scripts {
      initialization_units.push(
        @native.BridgeInitializationUnit::new(
          id,
          "script-" + index.to_string(),
          script,
        ),
      )
    }
  }
  BridgeFrontendConfig::{ extensions, initialization_units }
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
) -> Unit raise AppRunError {
  let fields : Map[String, Json] = { "command_id": Json::string(command_id) }
  match focused_window {
    Some(window) => fields["window"] = Json::string(window.to_string())
    None => ()
  }
  window.emit_bridge_event_json(
    bridge_event_json(
      "frontend",
      "menu.command",
      Json::object(fields),
      None,
      None,
    ),
  ) catch {
    error => raise native_run_error("forward menu command", error)
  }
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
) -> async (@ipc.IpcExtensionEvent) -> Unit noraise {
  fn(event) {
    window.emit_bridge_event_json(
      bridge_event_json(
        "extension",
        event.event_name,
        event.payload,
        Some(event.extension_namespace),
        page_instance,
      ),
    ) catch {
      _ => ()
    }
  }
}

///|
async fn dispatch_bridge_request(
  window : @native.Window,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
  policy : BridgePagePolicy,
  wake_signal : @core.RuntimeWakeSignal,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  let request_context = @core.AppCommandRequestContext::new(
    request.window(),
    wake_signal~,
  )
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
) -> BridgePagePolicy raise AppConfigurationError {
  if !proton_dev_mode_enabled() {
    return default_bridge_page_policy()
  }
  match manifest.entry {
    @manifest.AppEntry::Url(url) =>
      BridgePagePolicy::{
        dev_origin: Some(url_origin(url)),
        request_timeout_ms: 30000,
      }
    _ => default_bridge_page_policy()
  }
}

///|
fn url_origin(url : String) -> String raise AppConfigurationError {
  let (scheme_view, rest_view) = match url.split_once("://") {
    Some(parts) => parts
    None =>
      raise InvalidDevelopmentUrl(
        url~,
        reason="URL must include http:// or https://",
      )
  }
  let scheme = scheme_view.to_owned().to_lower()
  if scheme != "http" && scheme != "https" {
    raise InvalidDevelopmentUrl(url~, reason="URL must use http or https")
  }
  let rest = rest_view.to_owned()
  if rest == "" {
    raise InvalidDevelopmentUrl(url~, reason="URL is missing a host")
  }
  let mut end = rest.length()
  for delimiter in ["/", "?", "#"] {
    match rest.find(delimiter) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  if end == 0 {
    raise InvalidDevelopmentUrl(url~, reason="URL is missing a host")
  }
  let authority = rest.unsafe_substring(start=0, end~).to_string()
  if !dev_origin_authority_is_valid(authority) {
    raise InvalidDevelopmentUrl(url~, reason="URL has an invalid origin")
  }
  scheme + "://" + canonical_dev_origin_authority(authority, scheme, url)
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
  source_url : String,
) -> String raise AppConfigurationError {
  if authority.has_prefix("[") {
    let (host_part, suffix) = match authority.split_once("]") {
      Some(parts) => parts
      None =>
        raise InvalidDevelopmentUrl(
          url=source_url,
          reason="URL has an invalid IPv6 origin",
        )
    }
    let host_text = host_part.to_owned()
    let host = host_text
      .unsafe_substring(start=1, end=host_text.length())
      .to_string()
    if host == "" {
      raise InvalidDevelopmentUrl(
        url=source_url,
        reason="URL host must not be empty",
      )
    }
    if suffix != "" && !suffix.has_prefix(":") {
      raise InvalidDevelopmentUrl(
        url=source_url,
        reason="URL has an invalid IPv6 origin",
      )
    }
    "[" +
    host.to_lower() +
    "]" +
    canonical_dev_origin_port_suffix(suffix.to_owned(), scheme, source_url)
  } else {
    let first_colon = authority.find(":")
    let last_colon = authority.rev_find(":")
    if first_colon != last_colon {
      raise InvalidDevelopmentUrl(
        url=source_url,
        reason="IPv6 origins must use brackets",
      )
    }
    match first_colon {
      None => authority.to_lower()
      Some(index) => {
        let host = authority.unsafe_substring(start=0, end=index).to_string()
        let port = authority
          .unsafe_substring(start=index + 1, end=authority.length())
          .to_string()
        if host == "" {
          raise InvalidDevelopmentUrl(
            url=source_url,
            reason="URL host must not be empty",
          )
        }
        if port == "" {
          raise InvalidDevelopmentUrl(
            url=source_url,
            reason="URL port must not be empty",
          )
        }
        host.to_lower() +
        canonical_dev_origin_port_suffix(port, scheme, source_url)
      }
    }
  }
}

///|
fn canonical_dev_origin_port_suffix(
  port : String,
  scheme : String,
  source_url : String,
) -> String raise AppConfigurationError {
  if port == "" {
    return ""
  }
  let text = if port.has_prefix(":") { port[1:].to_owned() } else { port }
  if text == "" {
    raise InvalidDevelopmentUrl(
      url=source_url,
      reason="URL port must not be empty",
    )
  }
  let value = @string.parse_int(text[:]) catch {
    _ =>
      raise InvalidDevelopmentUrl(
        url=source_url,
        reason="URL port must be an integer: " + text,
      )
  }
  if value <= 0 || value > 65535 {
    raise InvalidDevelopmentUrl(
      url=source_url,
      reason="URL port is out of range: " + text,
    )
  }
  let default_port = if scheme == "http" { 80 } else { 443 }
  if value == default_port {
    ""
  } else {
    ":" + value.to_string()
  }
}

///|
fn bridge_page_policy_dev_origins(policy : BridgePagePolicy) -> Array[String] {
  match policy.dev_origin {
    Some(origin) => [origin]
    None => []
  }
}
