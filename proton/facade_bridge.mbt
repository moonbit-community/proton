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
  let visit_state : Map[String, Int] = {}
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
fn build_command_proxy_script(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[String?, String] {
  let specs : Array[Json] = []
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
    let apis : Array[Json] = []
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
      apis.push(Json::string(api_name))
    }
    specs.push(
      Json::object({
        "namespace": Json::string(js_namespace),
        "apis": Json::array(apis),
      }),
    )
    for script in spec.scripts() {
      scripts.push(script)
    }
  }
  if specs.length() == 0 {
    Ok(None)
  } else {
    let script = command_proxy_bootstrap_script(Json::array(specs).stringify())
    if scripts.length() == 0 {
      Ok(Some(script))
    } else {
      Ok(Some(script + "\n" + scripts.join("\n")))
    }
  }
}

///|
fn command_proxy_name_is_invalid(name : String) -> Bool {
  name.trim().to_owned() == "" ||
  name == "core" ||
  name == "events" ||
  @proton_command.app_command_js_property_is_reserved(name)
}

///|
fn command_proxy_bootstrap_script(specs_json : String) -> String {
  "(function(){\n" +
  "  var specs = " +
  specs_json +
  ";\n" +
  "  var existing = window.__MoonBit__;\n" +
  "  var root = existing && typeof existing === 'object' ? existing : {};\n" +
  "  var exactListeners = root['@@exactListeners'] && typeof root['@@exactListeners'] === 'object' ? root['@@exactListeners'] : Object.create(null);\n" +
  "  root['@@exactListeners'] = exactListeners;\n" +
  "  var events = root.events && typeof root.events === 'object' ? root.events : {};\n" +
  "  function ensureExactListeners(name) {\n" +
  "    if (!Array.isArray(exactListeners[name])) { exactListeners[name] = []; }\n" +
  "    return exactListeners[name];\n" +
  "  }\n" +
  "  function emitExact(name, event) {\n" +
  "    var listeners = ensureExactListeners(name).slice();\n" +
  "    for (var index = 0; index < listeners.length; index += 1) {\n" +
  "      listeners[index](event);\n" +
  "    }\n" +
  "    return event;\n" +
  "  }\n" +
  "  events.emit = function(name, event) { return emitExact(String(name), event); };\n" +
  "  events['@@emitExtensionEvent'] = function(namespace, eventName, payload) {\n" +
  "    var event = {\n" +
  "      extension: String(namespace),\n" +
  "      name: String(eventName),\n" +
  "      payload: payload === undefined ? null : payload\n" +
  "    };\n" +
  "    return emitExact(event.extension + '.' + event.name, event);\n" +
  "  };\n" +
  "  events.on = function(name, listener) {\n" +
  "    if (typeof listener !== 'function') {\n" +
  "      throw new TypeError('MoonBit.events.on expects a listener function');\n" +
  "    }\n" +
  "    var key = String(name);\n" +
  "    ensureExactListeners(key).push(listener);\n" +
  "    return function() {\n" +
  "      var listeners = ensureExactListeners(key);\n" +
  "      exactListeners[key] = listeners.filter(function(candidate) { return candidate !== listener; });\n" +
  "    };\n" +
  "  };\n" +
  "  root.events = events;\n" +
  "  function invokeExtension(namespace, apiName, payload) {\n" +
  "    var current = window.__MoonBit__;\n" +
  "    var core = current && current.core;\n" +
  "    if (!core || typeof core.invokeOp !== 'function') {\n" +
  "      return Promise.reject(new Error('MoonBit bridge is not available'));\n" +
  "    }\n" +
  "    return core.invokeOp('ext:' + namespace + '/' + apiName, payload);\n" +
  "  }\n" +
  "  var extensions = root['@@extensions'] && typeof root['@@extensions'] === 'object' ? root['@@extensions'] : Object.create(null);\n" +
  "  root['@@extensions'] = extensions;\n" +
  "  root['@@ensureExtension'] = function(extensionName) {\n" +
  "    var existingExtension = extensions[extensionName];\n" +
  "    if (existingExtension && typeof existingExtension === 'object') {\n" +
  "      return existingExtension;\n" +
  "    }\n" +
  "    var target = {};\n" +
  "    target.invoke = function(apiName, payload) {\n" +
  "      return invokeExtension(String(extensionName), String(apiName), payload);\n" +
  "    };\n" +
  "    target.on = function(eventName, listener) {\n" +
  "      return events.on(String(extensionName) + '.' + String(eventName), listener);\n" +
  "    };\n" +
  "    Object.defineProperty(target, 'name', { value: String(extensionName), enumerable: true });\n" +
  "    extensions[extensionName] = target;\n" +
  "    root[extensionName] = target;\n" +
  "    return target;\n" +
  "  };\n" +
  "  for (var i = 0; i < specs.length; i += 1) {\n" +
  "    var namespace = String(specs[i].namespace || '');\n" +
  "    var apis = Array.isArray(specs[i].apis) ? specs[i].apis : [];\n" +
  "    if (!namespace) { continue; }\n" +
  "    var target = root['@@ensureExtension'](namespace);\n" +
  "    target.invoke = (function(ns) {\n" +
  "      return function(apiName, payload) {\n" +
  "        return invokeExtension(ns, String(apiName), payload);\n" +
  "      };\n" +
  "    })(namespace);\n" +
  "    target.on = (function(ns) {\n" +
  "      return function(eventName, listener) {\n" +
  "        return events.on(ns + '.' + String(eventName), listener);\n" +
  "      };\n" +
  "    })(namespace);\n" +
  "    for (var j = 0; j < apis.length; j += 1) {\n" +
  "      var apiName = String(apis[j] || '');\n" +
  "      if (!apiName || apiName === 'then') { continue; }\n" +
  "      target[apiName] = (function(ns, api) {\n" +
  "        return function(payload) { return invokeExtension(ns, api, payload); };\n" +
  "      })(namespace, apiName);\n" +
  "    }\n" +
  "    root[namespace] = target;\n" +
  "  }\n" +
  "  window.__MoonBit__ = root;\n" +
  "})();"
}

///|
fn install_extension_event_sender(
  window : @native.Window,
  host : @core.AppCommandHost,
  policy : BridgePagePolicy,
) -> Unit {
  host.set_event_sender(extension_event_sender(window, None, policy))
}

///|
fn extension_event_sender(
  window : @native.Window,
  page_instance : String?,
  policy : BridgePagePolicy,
) -> async (@ipc.IpcExtensionEvent) -> Unit {
  async fn(event) {
    ignore(
      window.eval(extension_event_dispatch_script(event, page_instance, policy)),
    )
    @async.sleep(0)
  }
}

///|
fn extension_event_dispatch_script(
  event : @ipc.IpcExtensionEvent,
  page_instance : String?,
  policy : BridgePagePolicy,
) -> String {
  let page_instance_check = match page_instance {
    Some(value) =>
      "  if (!root || !root.core || root.core['@@pageInstance'] !== " +
      Json::string(value).stringify() +
      ") { return; }\n"
    None => ""
  }
  "(function(){\n" +
  bridge_page_policy_guard_script(policy) +
  "  var event = " +
  ToJson::to_json(event).stringify() +
  ";\n" +
  "  var root = window.__MoonBit__;\n" +
  page_instance_check +
  "  var events = root && root.events;\n" +
  "  var emit = events && events['@@emitExtensionEvent'];\n" +
  "  if (typeof emit === 'function') {\n" +
  "    emit(event.extension_namespace, event.event_name, event.payload);\n" +
  "  }\n" +
  "})();"
}

///|
async fn dispatch_bridge_request(
  window : @native.Window,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
  policy : BridgePagePolicy,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  let response = host.dispatch_ipc_with_event_sender(
    @ipc.IpcOpRequest::new(
      request_id.to_string(),
      request.op(),
      request.payload(),
    ),
    Some(extension_event_sender(window, request.page_instance(), policy)),
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
fn default_bridge_page_policy() -> BridgePagePolicy {
  BridgePagePolicy::{ dev_origin: None }
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
        BridgePagePolicy::{ dev_origin: Some(origin) }
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
  Ok(scheme + "://" + authority)
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
fn bridge_page_policy_dev_origins(policy : BridgePagePolicy) -> Array[String] {
  match policy.dev_origin {
    Some(origin) => [origin]
    None => []
  }
}

///|
fn bridge_page_policy_guard_script(policy : BridgePagePolicy) -> String {
  match policy.dev_origin {
    None =>
      "  if (!window.location || window.location.protocol !== 'proton:') { return; }\n"
    Some(origin) =>
      "  if (!window.location) { return; }\n" +
      "  if (window.location.protocol !== 'proton:' && window.location.origin !== " +
      Json::string(origin).stringify() +
      ") { return; }\n"
  }
}
