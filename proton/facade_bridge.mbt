///|
fn build_command_host(
  command_capabilities : Array[AppCommandCapability],
  extension_capabilities : Array[ExtensionCapabilityBinding],
) -> CommandHostBuild raise AppRunError {
  let host = @core.AppCommandHost::new(
    expose_error_details=proton_dev_mode_enabled(),
  )
  let destroy_hooks : Array[CommandExtensionDestroyHook] = []
  let app_capabilities : Array[RegisteredAppCommandCapability] = []
  let mut has_commands = false
  let registrar = @proton_command.CommandRegistrar::new(host)
  for capability in command_capabilities {
    let registered_before = host.registered_ops().length()
    (capability.register)(registrar) catch {
      error => {
        ignore(close_command_host_runtime(host, destroy_hooks))
        raise CommandExtensionLifecycleError(
          ApplicationRegistrationFailed(detail=@debug.render(Repr(error))),
        )
      }
    }
    let registered = host.registered_ops()
    let ops : Array[String] = []
    for index in registered_before..<registered.length() {
      ops.push(registered[index])
    }
    if !ops.is_empty() {
      has_commands = true
    }
    app_capabilities.push(RegisteredAppCommandCapability::{
      ops,
      targets: capability.targets.copy(),
    })
  }
  let command_extensions = command_extension_specs(extension_capabilities) catch {
    error => {
      ignore(close_command_host_runtime(host, destroy_hooks))
      raise ConfigurationError(error)
    }
  }
  let ordered_ids = command_extension_order(command_extensions) catch {
    error => {
      ignore(close_command_host_runtime(host, destroy_hooks))
      raise ConfigurationError(error)
    }
  }
  for id in ordered_ids {
    let spec = command_extensions[id]
    destroy_hooks.push(CommandExtensionDestroyHook::{
      extension_id: id,
      callback: fn() raise { spec.destroy() },
    })
    spec.register(registrar) catch {
      error => {
        let primary = CommandExtensionLifecycleError(
          RegistrationFailed(extension_id=id, detail=@debug.render(Repr(error))),
        )
        let cleanup_failures : Array[AppCleanupError] = []
        for failure in close_command_host_runtime(host, destroy_hooks) {
          cleanup_failures.push(CommandExtension(failure))
        }
        match cleanup_run_error(Some(primary), cleanup_failures) {
          Some(combined) => raise combined
          None => raise primary
        }
      }
    }
    has_commands = true
  }
  if has_commands {
    host.seal_registrations()
    CommandHostBuild::{
      runtime: Some(CommandHostRuntime::{ host, destroy_hooks, closed: false, }),
      app_capabilities,
    }
  } else {
    ignore(close_command_host_runtime(host, destroy_hooks))
    CommandHostBuild::{ runtime: None, app_capabilities, }
  }
}

///|
fn command_extension_specs(
  capabilities : Array[ExtensionCapabilityBinding],
) -> Map[String, @proton_command.AppCommandExtensionSpec] raise AppConfigurationError {
  let specs : Map[String, @proton_command.AppCommandExtensionSpec] = Map([])
  for capability in capabilities {
    let id = capability.spec.id()
    match specs.get(id) {
      Some(existing) => {
        guard extension_specs_match(existing, capability.spec) else {
          raise InvalidRendererCapability(
            detail="extension " + id + " has conflicting definitions",
          )
        }
      }
      None => specs[id] = capability.spec
    }
  }
  specs
}

///|
fn extension_specs_match(
  first : @proton_command.AppCommandExtensionSpec,
  second : @proton_command.AppCommandExtensionSpec,
) -> Bool {
  first.js_namespace() == second.js_namespace() &&
  first.op_names() == second.op_names() &&
  first.dependencies() == second.dependencies() &&
  first.scripts() == second.scripts()
}

///|
fn close_command_host_runtime(
  host : @core.AppCommandHost,
  destroy_hooks : Array[CommandExtensionDestroyHook],
) -> Array[CommandExtensionLifecycleError] {
  let failures : Array[CommandExtensionLifecycleError] = []
  let hook_count = destroy_hooks.length()
  for index in 0..<hook_count {
    let hook = destroy_hooks[hook_count - index - 1]
    (hook.callback)() catch {
      error =>
        failures.push(
          DestroyFailed(
            extension_id=hook.extension_id,
            detail=@debug.render(Repr(error)),
          ),
        )
    }
  }
  host.close()
  failures
}

///|
fn command_extension_order(
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Array[String] raise AppConfigurationError {
  let visit_state : Map[String, Int] = Map([])
  let ordered : Array[String] = []
  for id, _spec in command_extensions {
    visit_command_extension(id, None, command_extensions, visit_state, ordered)
  }
  ordered
}

///|
fn visit_command_extension(
  id : String,
  requested_by : String?,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  visit_state : Map[String, Int],
  ordered : Array[String],
) -> Unit raise AppConfigurationError {
  match visit_state.get(id) {
    Some(2) => return
    Some(1) => raise ExtensionDependencyCycle(extension_id=id)
    _ => ()
  }
  let spec = require_command_extension(id, requested_by, command_extensions)
  visit_state[id] = 1
  for dependency in spec.dependencies() {
    visit_command_extension(
      dependency,
      Some(id),
      command_extensions,
      visit_state,
      ordered,
    )
  }
  visit_state[id] = 2
  ordered.push(id)
}

///|
fn require_command_extension(
  id : String,
  requested_by : String?,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> @proton_command.AppCommandExtensionSpec raise AppConfigurationError {
  match command_extensions.get(id) {
    Some(spec) => spec
    None =>
      raise ExtensionUnavailable(
        extension_id=id,
        requested_by~,
        state="missing",
      )
  }
}

///|
fn bridge_frontend_config_for_extension(
  id : String,
  spec : @proton_command.AppCommandExtensionSpec,
) -> BridgeFrontendConfig raise AppConfigurationError {
  let extensions : Array[@native.BridgeExtensionConfig] = []
  let initialization_units : Array[@native.BridgeInitializationUnit] = []
  append_bridge_extension_frontend(id, spec, extensions, initialization_units)
  BridgeFrontendConfig::{ extensions, initialization_units, }
}

///|
fn append_bridge_extension_frontend(
  id : String,
  spec : @proton_command.AppCommandExtensionSpec,
  extensions : Array[@native.BridgeExtensionConfig],
  initialization_units : Array[@native.BridgeInitializationUnit],
) -> Unit raise AppConfigurationError {
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

///|
/// Reports whether a name cannot be exposed as a bridge proxy on the renderer
/// root object. `app` is reserved alongside `core` and `events` because the
/// bridge publishes granted application commands under it.
fn command_proxy_name_is_invalid(name : String) -> Bool {
  name.trim().to_owned() == "" ||
  name == "core" ||
  name == "events" ||
  name == "app" ||
  @proton_command.app_command_js_property_is_reserved(name)
}

///|
fn forward_menu_command(
  window : @native.Window,
  command_id : String,
  focused_window : Int64?,
) -> Unit raise AppRunError {
  let fields : Map[String, Json] = { "command_id": command_id }
  match focused_window {
    Some(window) => fields["window"] = Json(window.to_string())
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
    error =>
      if !is_ignorable_frontend_event_forward_error(error) {
        raise native_run_error("forward menu command", error)
      }
  }
}

///|
fn forward_extension_event(
  window : @native.Window,
  extension_namespace : String,
  name : String,
  payload : Json,
) -> Unit raise AppRunError {
  window.emit_bridge_event_json(
    bridge_event_json(
      "extension",
      name,
      payload,
      Some(extension_namespace),
      None,
    ),
  ) catch {
    error =>
      if !is_ignorable_frontend_event_forward_error(error) {
        raise native_run_error("forward extension event", error)
      }
  }
}

///|
fn is_ignorable_frontend_event_forward_error(
  error : @native.NativeError,
) -> Bool {
  error.is_invalid_state() || error.is_stale_window_request()
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
    "kind": kind,
    "name": name,
    "payload": payload,
  }
  match extension {
    Some(value) => fields["extension"] = Json(value)
    None => ()
  }
  match page_instance {
    Some(value) => fields["page_instance"] = Json(value)
    None => ()
  }
  Json::object(fields).stringify()
}

///|
fn typed_event_sender(
  window : @native.Window,
  page_instance : String?,
) -> async (@proton_contract.ContractRoute, String, Json) -> Unit noraise {
  fn(route, name, payload) {
    let event_json = if route.is_application() {
      bridge_event_json("frontend", name, payload, None, page_instance)
    } else {
      match route.extension_namespace() {
        Some(extension_namespace) =>
          bridge_event_json(
            "extension",
            name,
            payload,
            Some(extension_namespace),
            page_instance,
          )
        None => return
      }
    }
    window.emit_bridge_event_json(event_json) catch {
      _ => ()
    }
  }
}

///|
async fn dispatch_bridge_request(
  window : @native.Window,
  window_id : String,
  permissions : WindowPermissionPolicy,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
  wake_signal : @core.RuntimeWakeSignal,
  dialog_completions : DialogCompletionStore,
  locale_preferences : @locale.LocalePreferences,
) -> @native.BridgeResponse {
  let grant = match
    permissions.grant_for_request(request.source_origin(), request.op()) {
    Some(grant) => grant
    None =>
      return @native.BridgeResponse::Err(
        request_id=request.request_id(),
        code="permission_denied",
        message="the page is not permitted to invoke this operation",
      )
  }
  let result : Ref[@native.BridgeResponse?] = Ref(None)
  @async.with_task_group(command_tasks => {
    result.val = Some(
      dispatch_bridge_request_in_command_scope(
        window, window_id, grant, host, request, wake_signal, dialog_completions,
        command_tasks, locale_preferences,
      ),
    )
    command_tasks.return_immediately(())
  })
  result.val.unwrap()
}

///|
async fn dispatch_bridge_request_in_command_scope(
  window : @native.Window,
  window_id : String,
  grant : ResolvedPermissionGrant,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
  wake_signal : @core.RuntimeWakeSignal,
  dialog_completions : DialogCompletionStore,
  command_tasks : @async.TaskGroup[Unit],
  locale_preferences : @locale.LocalePreferences,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  let request_context = @core.AppCommandRequestContext::new(
    command_tasks,
    locale_preferences,
    window=command_window_capability(window.as_ref(), dialog_completions),
    window_id~,
    source_origin=request.source_origin(),
    page_instance=request.page_instance(),
    permission_extension=grant.extension_id,
    permission_scope=grant.scope,
    wake_signal~,
    emit_event=typed_event_sender(window, request.page_instance()),
  )
  let response = host.dispatch_ipc_with_context(
    request_context,
    @ipc.IpcOpRequest::new(
      request_id.to_string(),
      request.op(),
      request.payload(),
    ),
  )
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
fn command_dialog_level(level : String) -> @native.DialogLevel {
  match level {
    "warning" => @native.DialogLevel::Warning
    "error" => @native.DialogLevel::Error
    _ => @native.DialogLevel::Info
  }
}

///|
async fn wait_for_command_dialog(
  window : @native.WindowRef,
  completions : DialogCompletionStore,
  dialog : Int64,
) -> String {
  defer (window.cancel_dialog(dialog) catch { _ => () })
  completions.wait(dialog)
}

///|
fn command_window_capability(
  window : @native.WindowRef,
  dialog_completions : DialogCompletionStore,
) -> @core.CommandWindow {
  @core.CommandWindow::new(
    async fn(title, message, level) {
      let dialog = window.begin_message_dialog(
        title,
        message,
        command_dialog_level(level),
      )
      ignore(wait_for_command_dialog(window, dialog_completions, dialog))
    },
    async fn(title, message, level) {
      let dialog = window.begin_confirm_dialog(
        title,
        message,
        command_dialog_level(level),
      )
      wait_for_command_dialog(window, dialog_completions, dialog) == "1"
    },
    async fn(title, path) {
      let dialog = window.begin_open_file_dialog(title, path)
      let result = wait_for_command_dialog(window, dialog_completions, dialog)
      if result.is_empty() {
        None
      } else {
        Some(result)
      }
    },
    async fn(title, path) {
      let dialog = window.begin_save_file_dialog(title, path)
      let result = wait_for_command_dialog(window, dialog_completions, dialog)
      if result.is_empty() {
        None
      } else {
        Some(result)
      }
    },
    async fn(title, path) {
      let dialog = window.begin_choose_directory_dialog(title, path)
      let result = wait_for_command_dialog(window, dialog_completions, dialog)
      if result.is_empty() {
        None
      } else {
        Some(result)
      }
    },
  )
}

///|
fn default_bridge_page_policy() -> BridgePagePolicy {
  BridgePagePolicy::{ entry_origin: None, }
}

///|
fn bridge_page_policy_for_entry(
  entry : @manifest.AppEntry,
) -> BridgePagePolicy raise AppConfigurationError {
  match entry {
    @manifest.AppEntry::Url(url) =>
      BridgePagePolicy::{ entry_origin: Some(url_origin(url)), }
    _ => default_bridge_page_policy()
  }
}

///|
fn url_origin(url : String) -> String raise AppConfigurationError {
  let (scheme_view, rest_view) = match url.split_once("://") {
    Some(parts) => parts
    None =>
      raise InvalidEntryUrl(url~, reason="URL must include http:// or https://")
  }
  let scheme = scheme_view.to_owned().to_lower()
  if scheme != "http" && scheme != "https" {
    raise InvalidEntryUrl(url~, reason="URL must use http or https")
  }
  let rest = rest_view.to_owned()
  if rest == "" {
    raise InvalidEntryUrl(url~, reason="URL is missing a host")
  }
  let mut end = rest.length()
  for delimiter in ["/", "?", "#"] {
    match rest.find(delimiter) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  if end == 0 {
    raise InvalidEntryUrl(url~, reason="URL is missing a host")
  }
  let authority = rest.unsafe_substring(start=0, end~).to_string()
  if !entry_origin_authority_is_valid(authority) {
    raise InvalidEntryUrl(url~, reason="URL has an invalid origin")
  }
  scheme + "://" + canonical_entry_origin_authority(authority, scheme, url)
}

///|
fn entry_origin_authority_is_valid(authority : String) -> Bool {
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
fn canonical_entry_origin_authority(
  authority : String,
  scheme : String,
  source_url : String,
) -> String raise AppConfigurationError {
  if authority.has_prefix("[") {
    let (host_part, suffix) = match authority.split_once("]") {
      Some(parts) => parts
      None =>
        raise InvalidEntryUrl(
          url=source_url,
          reason="URL has an invalid IPv6 origin",
        )
    }
    let host_text = host_part.to_owned()
    let host = host_text
      .unsafe_substring(start=1, end=host_text.length())
      .to_string()
    if host == "" {
      raise InvalidEntryUrl(url=source_url, reason="URL host must not be empty")
    }
    if suffix != "" && !suffix.has_prefix(":") {
      raise InvalidEntryUrl(
        url=source_url,
        reason="URL has an invalid IPv6 origin",
      )
    }
    "[" +
    host.to_lower() +
    "]" +
    canonical_entry_origin_port_suffix(suffix.to_owned(), scheme, source_url)
  } else {
    let first_colon = authority.find(":")
    let last_colon = authority.rev_find(":")
    if first_colon != last_colon {
      raise InvalidEntryUrl(
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
          raise InvalidEntryUrl(
            url=source_url,
            reason="URL host must not be empty",
          )
        }
        if port == "" {
          raise InvalidEntryUrl(
            url=source_url,
            reason="URL port must not be empty",
          )
        }
        host.to_lower() +
        canonical_entry_origin_port_suffix(port, scheme, source_url)
      }
    }
  }
}

///|
fn canonical_entry_origin_port_suffix(
  port : String,
  scheme : String,
  source_url : String,
) -> String raise AppConfigurationError {
  if port == "" {
    return ""
  }
  let text = if port.has_prefix(":") { port[1:].to_owned() } else { port }
  if text == "" {
    raise InvalidEntryUrl(url=source_url, reason="URL port must not be empty")
  }
  let value = @string.parse_int(text[:]) catch {
    _ =>
      raise InvalidEntryUrl(
        url=source_url,
        reason="URL port must be an integer: " + text,
      )
  }
  if value <= 0 || value > 65535 {
    raise InvalidEntryUrl(
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
