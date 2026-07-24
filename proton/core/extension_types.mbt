///|
/// Runtime abstraction for a Proton extension.
struct Extension {
  id : String
  js_namespace : String
  register : (ExtensionContext) -> Unit raise
  on_install : (ExtensionContext) -> Unit raise
  on_destroy : (ExtensionContext) -> Unit raise
  scripts : Array[String]
}

///|
/// Registration context handed to an extension during installation.
struct ExtensionContext {
  host : ExtensionHost
  extension_id : String
  extension_namespace : String
}

///|
/// Host wrapper for registering extension metadata and native op handlers.
struct ExtensionHost {
  extension_ids : Map[String, String]
  extension_namespaces : Map[String, String]
  apis : Map[String, Bool]
  api_names : Map[String, Array[String]]
  destroy_hooks : Map[String, () -> Unit raise]
  op_registry : OpRegistry
}

///|
/// Builds an extension value that can later be installed on an `ExtensionHost`.
pub fn Extension::new(
  id : String,
  js_namespace : String,
  register : (ExtensionContext) -> Unit raise,
  on_install? : (ExtensionContext) -> Unit raise = fn(_context) {  },
  on_destroy? : (ExtensionContext) -> Unit raise = fn(_context) {  },
  scripts? : Array[String] = [],
) -> Extension {
  Extension::{
    id,
    js_namespace,
    register,
    on_install,
    on_destroy,
    scripts: scripts.map(fn(script) { script }),
  }
}

///|
/// Returns the stable extension id.
pub fn Extension::id(self : Extension) -> String {
  self.id
}

///|
/// Returns the JavaScript namespace exposed by this extension.
pub fn Extension::js_namespace(self : Extension) -> String {
  self.js_namespace
}

///|
/// Returns the stable extension id currently being installed.
pub fn ExtensionContext::id(self : ExtensionContext) -> String {
  self.extension_id
}

///|
/// Returns the JavaScript namespace currently being installed.
pub fn ExtensionContext::js_namespace(self : ExtensionContext) -> String {
  self.extension_namespace
}

///|
/// Emits an extension-scoped event through the host.
pub fn[Payload : ToJson] ExtensionContext::emit(
  self : ExtensionContext,
  event_name : String,
  payload : Payload,
) -> Unit raise ExtensionHostError {
  self.host.emit(self.extension_namespace, event_name, payload)
}

///|
/// Registers a typed extension op.
pub fn[Payload : @json.FromJson, Reply : ToJson] ExtensionContext::op(
  self : ExtensionContext,
  api_name : String,
  callback : (Payload) -> Reply raise?,
) -> Unit raise {
  let op_name = self.register_api(api_name)
  self.host.op_registry.handle(op_name, fn(payload) raise { callback(payload) })
}

///|
/// Returns the installed JavaScript helper scripts owned by this extension.
pub fn Extension::scripts(self : Extension) -> Array[String] {
  self.scripts.map(fn(script) { script })
}
