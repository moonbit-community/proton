///|
/// High-level application facade for ordinary Proton apps.
struct App {
  file_path : String?
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  mut debug_level_value : Int
  mut title_overridden : Bool
  mut size_overridden : Bool
  mut entry_overridden : Bool
  mut debug_overridden : Bool
  extension_settings : Map[String, @manifest.ExtensionSetting]
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec]
  validation_errors : Array[String]
}

///|
priv struct BridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}

///|
/// Creates an inline HTML application.
pub fn html(
  title : String,
  html : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Html(html),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline URL application.
pub fn url(
  title : String,
  url : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Url(url),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline file application.
pub fn file(
  title : String,
  path : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::File(path),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline asset application.
pub fn asset(
  title : String,
  path : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an application backed by a `moon.proton` config file.
pub fn config(path : String) -> App {
  App::{
    file_path: Some(path),
    window: @manifest.WindowManifest::new(
      "Proton",
      900,
      700,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    entry: @manifest.AppEntry::Html(""),
    debug_level_value: 0,
    title_overridden: false,
    size_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
    extension_settings: {},
    command_extensions: {},
    validation_errors: [],
  }
}

///|
/// Enables or disables runtime debug mode.
pub fn App::debug(self : App, enabled? : Bool = true) -> App {
  self.debug_level(debug_level_from_bool(enabled))
}

///|
/// Sets the runtime debug level.
pub fn App::debug_level(self : App, debug : Int) -> App {
  self.debug_overridden = true
  self.debug_level_value = debug
  self
}

///|
/// Sets the primary window title.
pub fn App::title(self : App, title : String) -> App {
  self.title_overridden = true
  self.window = @manifest.WindowManifest::new(
    title,
    self.window.width,
    self.window.height,
    size_hint=self.window.size_hint,
  )
  self
}

///|
/// Sets the primary window size.
pub fn App::size(self : App, width~ : Int, height~ : Int) -> App {
  self.size_overridden = true
  self.window = @manifest.WindowManifest::new(
    self.window.title,
    width,
    height,
    size_hint=self.window.size_hint,
  )
  self
}

///|
/// Overrides the primary app entry with inline HTML.
pub fn App::entry_html(self : App, html : String) -> App {
  self.set_entry(@manifest.AppEntry::Html(html))
}

///|
/// Overrides the primary app entry with a URL.
pub fn App::entry_url(self : App, url : String) -> App {
  self.set_entry(@manifest.AppEntry::Url(url))
}

///|
/// Overrides the primary app entry with a file path.
pub fn App::entry_file(self : App, path : String) -> App {
  self.set_entry(@manifest.AppEntry::File(path))
}

///|
/// Overrides the primary app entry with an asset path.
pub fn App::entry_asset(self : App, path : String) -> App {
  self.set_entry(@manifest.AppEntry::Asset(path))
}

///|
/// Registers one extension setting with the app facade.
///
/// The native DLL route exposes command extensions through
/// `window.__MoonBit__.core.invokeOp(...)` and a generated high-level proxy for
/// inline HTML entries.
pub fn App::extension(
  self : App,
  extension : @proton_extension.Extension,
  options? : Json,
) -> App {
  let id = extension.id()
  if id.trim().to_owned() == "" {
    self.validation_errors.push("extension id must not be empty")
  } else {
    self.extension_settings[id] = @manifest.ExtensionSetting::enabled(options~)
    match extension.command_spec() {
      Some(spec) => self.command_extensions[id] = spec
      None => ()
    }
  }
  self
}

///|
/// Registers a set of extension settings with the app facade.
pub fn App::extensions(
  self : App,
  extensions : @proton_extension.Extensions,
) -> App {
  for extension in extensions.items() {
    ignore(self.extension(extension))
  }
  self
}

///|
/// Runs the configured app through the native Proton runtime.
pub async fn App::run(self : App) -> Result[Unit, String] {
  @async.sleep(0)
  match self.validation_error() {
    Some(error) => return Err(error)
    None => ()
  }
  match self.resolved_manifest() {
    Err(error) => Err(error)
    Ok(manifest) => run_manifest(manifest, self.command_extensions)
  }
}

///|
/// Runs the configured app and aborts with the error message on failure.
pub async fn App::run_or_abort(self : App) -> Unit {
  match self.run() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
fn App::new(
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  debug : Int,
  size_hint : @manifest.WindowSizeHint,
) -> App {
  App::{
    file_path: None,
    window: @manifest.WindowManifest::new(title, width, height, size_hint~),
    entry,
    debug_level_value: debug,
    title_overridden: false,
    size_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
    extension_settings: {},
    command_extensions: {},
    validation_errors: [],
  }
}

///|
fn App::set_entry(self : App, entry : @manifest.AppEntry) -> App {
  self.entry_overridden = true
  self.entry = entry
  self
}

///|
fn App::validation_error(self : App) -> String? {
  self.validation_errors.get(0)
}

///|
fn App::resolved_manifest(self : App) -> Result[@manifest.AppManifest, String] {
  match self.file_path {
    Some(path) =>
      @bootstrap.load_config_manifest_from_file(path).map(fn(loaded) {
        self.merge_config(loaded.manifest())
      })
    None => Ok(self.inline_manifest())
  }
}

///|
fn App::inline_manifest(self : App) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    self.window,
    self.entry,
    debug=self.debug_level_value,
    extensions=self.extension_settings,
  )
}

///|
fn App::merge_config(
  self : App,
  manifest : @manifest.AppManifest,
) -> @manifest.AppManifest {
  let window = self.merged_window(manifest.window)
  let entry = if self.entry_overridden { self.entry } else { manifest.entry }
  let debug = if self.debug_overridden {
    self.debug_level_value
  } else {
    manifest.debug
  }
  let extensions = merge_extension_settings(
    manifest.extensions,
    self.extension_settings,
  )
  @manifest.AppManifest::new(
    window,
    entry,
    debug~,
    windows=manifest.windows,
    extensions~,
  )
}

///|
fn merge_extension_settings(
  base : Map[String, @manifest.ExtensionSetting],
  overrides : Map[String, @manifest.ExtensionSetting],
) -> Map[String, @manifest.ExtensionSetting] {
  let merged : Map[String, @manifest.ExtensionSetting] = {}
  for name, setting in base {
    merged[name] = setting
  }
  for name, setting in overrides {
    merged[name] = setting
  }
  merged
}

///|
fn App::merged_window(
  self : App,
  window : @manifest.WindowManifest,
) -> @manifest.WindowManifest {
  let title = if self.title_overridden {
    self.window.title
  } else {
    window.title
  }
  let width = if self.size_overridden {
    self.window.width
  } else {
    window.width
  }
  let height = if self.size_overridden {
    self.window.height
  } else {
    window.height
  }
  @manifest.WindowManifest::new(
    title,
    width,
    height,
    size_hint=window.size_hint,
  )
}

///|
async fn run_manifest(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[Unit, String] {
  let runtime = match
    @native.Runtime::new(
      config=@native.RuntimeConfig::bundled(
        remote_debugging_port=debug_port(manifest.debug),
      ),
    ) {
    Ok(runtime) => runtime
    Err(error) => return Err(native_error_message("create runtime", error))
  }
  let window = match
    @native.Window::new(
      runtime,
      config=@native.WindowConfig::new(
        title=manifest.window.title,
        width=manifest.window.width,
        height=manifest.window.height,
        initial_url="about:blank",
      ),
    ) {
    Ok(window) => window
    Err(error) => {
      ignore(runtime.destroy())
      return Err(native_error_message("create window", error))
    }
  }

  let command_host = match build_command_host(manifest, command_extensions) {
    Err(error) => {
      ignore(window.destroy())
      ignore(runtime.destroy())
      return Err(error)
    }
    Ok(host) => host
  }
  let command_proxy_script = match
    build_command_proxy_script(manifest, command_extensions) {
    Err(error) => {
      close_command_host(command_host)
      ignore(window.destroy())
      ignore(runtime.destroy())
      return Err(error)
    }
    Ok(script) => script
  }
  match command_host {
    Some(host) => {
      let ops = host.registered_ops()
      match
        native_unit_result(
          "install bridge",
          window.install_bridge(@native.BridgeConfig::new(ops~)),
        ) {
        Err(error) => {
          host.close()
          ignore(window.destroy())
          ignore(runtime.destroy())
          return Err(error)
        }
        Ok(_) => install_extension_event_sender(window, host)
      }
    }
    None => ()
  }
  match load_entry_after_create(window, manifest.entry, command_proxy_script) {
    Err(error) => {
      close_command_host(command_host)
      ignore(window.destroy())
      ignore(runtime.destroy())
      Err(error)
    }
    Ok(_) =>
      match native_unit_result("show window", window.show()) {
        Err(error) => {
          close_command_host(command_host)
          ignore(window.destroy())
          ignore(runtime.destroy())
          Err(error)
        }
        Ok(_) => {
          let run_result = match command_host {
            Some(host) => run_bridge_pump(runtime, window, host)
            None => run_window_pump(runtime)
          }
          close_command_host(command_host)
          let destroy_result = native_unit_result(
            "destroy runtime",
            runtime.destroy(),
          )
          match run_result {
            Err(error) => Err(error)
            Ok(_) => destroy_result
          }
        }
      }
  }
}

///|
fn build_command_host(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[@core.AppCommandHost?, String] {
  let host = @core.AppCommandHost::new()
  let mut has_commands = false
  for id, spec in command_extensions {
    match manifest.extension_setting(id) {
      Some(setting) =>
        if setting.is_enabled() {
          let context = @proton_command.AppCommandExtensionContext::new(
            host,
            id,
            spec.js_namespace(),
            options=setting.options(),
          )
          match spec.register(context) {
            Err(error) => {
              host.close()
              return Err(error)
            }
            Ok(_) => has_commands = true
          }
        }
      None => ()
    }
  }
  if has_commands {
    host.seal_registrations()
    Ok(Some(host))
  } else {
    host.close()
    Ok(None)
  }
}

///|
fn build_command_proxy_script(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[String?, String] {
  let specs : Array[Json] = []
  for id, spec in command_extensions {
    match manifest.extension_setting(id) {
      Some(setting) =>
        if setting.is_enabled() {
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
        }
      None => ()
    }
  }
  if specs.length() == 0 {
    Ok(None)
  } else {
    Ok(Some(command_proxy_bootstrap_script(Json::array(specs).stringify())))
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
  "  var exactListeners = Object.create(null);\n" +
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
  "  for (var i = 0; i < specs.length; i += 1) {\n" +
  "    var namespace = String(specs[i].namespace || '');\n" +
  "    var apis = Array.isArray(specs[i].apis) ? specs[i].apis : [];\n" +
  "    if (!namespace) { continue; }\n" +
  "    var target = root[namespace];\n" +
  "    if (!target || typeof target !== 'object') { target = {}; }\n" +
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
) -> Unit {
  host.set_event_sender(extension_event_sender(window, None))
}

///|
fn extension_event_sender(
  window : @native.Window,
  page_instance : String?,
) -> async (@ipc.IpcExtensionEvent) -> Unit {
  async fn(event) {
    ignore(window.eval(extension_event_dispatch_script(event, page_instance)))
    @async.sleep(0)
  }
}

///|
fn extension_event_dispatch_script(
  event : @ipc.IpcExtensionEvent,
  page_instance : String?,
) -> String {
  let page_instance_check = match page_instance {
    Some(value) =>
      "  if (!root || !root.core || root.core['@@pageInstance'] !== " +
      Json::string(value).stringify() +
      ") { return; }\n"
    None => ""
  }
  "(function(){\n" +
  "  if (!window.location || window.location.protocol !== 'proton:') { return; }\n" +
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
fn close_command_host(host : @core.AppCommandHost?) -> Unit {
  match host {
    Some(value) => value.close()
    None => ()
  }
}

///|
async fn run_window_pump(runtime : @native.Runtime) -> Result[Unit, String] {
  let mut closed = false
  let mut idle_delay = 0
  while !closed {
    let mut did_work = false
    match runtime.do_message_loop_work() {
      Err(error) => return Err(native_error_message("pump runtime", error))
      Ok(_) => ()
    }

    let mut polling_events = true
    while polling_events {
      match runtime.poll_event() {
        Err(error) => return Err(native_error_message("poll event", error))
        Ok(None) => polling_events = false
        Ok(Some(event)) => {
          did_work = true
          if event.is_window_closed() {
            closed = true
          }
        }
      }
    }

    if did_work {
      idle_delay = 0
      @async.sleep(0)
    } else {
      idle_delay = next_idle_delay(idle_delay)
      @async.sleep(idle_delay)
    }
  }
  Ok(())
}

///|
async fn run_bridge_pump(
  runtime : @native.Runtime,
  window : @native.Window,
  host : @core.AppCommandHost,
) -> Result[Unit, String] {
  @async.with_task_group(group => {
    let mut closed = false
    let mut idle_delay = 0
    let mut pending : Array[BridgeDispatchTask] = []
    while !closed {
      let mut did_work = false
      match runtime.do_message_loop_work() {
        Err(error) => return Err(native_error_message("pump runtime", error))
        Ok(_) => ()
      }

      let mut polling_events = true
      while polling_events {
        match runtime.poll_event() {
          Err(error) => return Err(native_error_message("poll event", error))
          Ok(None) => polling_events = false
          Ok(Some(event)) => {
            did_work = true
            if event.is_window_closed() {
              closed = true
            }
          }
        }
      }

      let mut polling_bridge = true
      while polling_bridge {
        match runtime.poll_bridge_request() {
          Err(error) =>
            return Err(native_error_message("poll bridge request", error))
          Ok(None) => polling_bridge = false
          Ok(Some(request)) => {
            did_work = true
            let request_id = request.request_id()
            let task = group.spawn(
              () => dispatch_bridge_request(window, host, request),
              no_wait=true,
              allow_failure=true,
            )
            pending.push(BridgeDispatchTask::{ request_id, task })
          }
        }
      }

      let remaining : Array[BridgeDispatchTask] = []
      for item in pending {
        let completed = item.task.try_wait() catch {
          _ =>
            Some(
              @native.BridgeResponse::Err(
                request_id=item.request_id,
                code="handler_failed",
                message="bridge handler task failed",
              ),
            )
        }
        match completed {
          Some(response) => {
            did_work = true
            match runtime.respond_bridge_request(response) {
              Err(error) =>
                if !is_stale_bridge_response_error(error) {
                  return Err(
                    native_error_message("respond bridge request", error),
                  )
                }
              Ok(_) => ()
            }
          }
          None => remaining.push(item)
        }
      }
      pending = remaining

      if did_work {
        idle_delay = 0
        @async.sleep(0)
      } else {
        idle_delay = next_idle_delay(idle_delay)
        @async.sleep(idle_delay)
      }
    }
    for item in pending {
      item.task.cancel()
    }
    Ok(())
  })
}

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  (error.status == -2 && error.message.contains("no longer pending")) ||
  (
    error.status == -7 &&
    error.message.contains("failed to send bridge response to renderer")
  )
}

///|
async fn dispatch_bridge_request(
  window : @native.Window,
  host : @core.AppCommandHost,
  request : @native.BridgeRequest,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  let response = host.dispatch_ipc_with_event_sender(
    @ipc.IpcOpRequest::new(
      request_id.to_string(),
      request.op(),
      request.payload(),
    ),
    Some(extension_event_sender(window, request.page_instance())),
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
fn next_idle_delay(current : Int) -> Int {
  if current <= 0 {
    1
  } else if current >= 16 {
    16
  } else {
    let next = current * 2
    if next > 16 {
      16
    } else {
      next
    }
  }
}

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
