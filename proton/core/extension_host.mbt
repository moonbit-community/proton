///|
/// Creates an extension host.
pub fn ExtensionHost::new() -> ExtensionHost {
  ExtensionHost::{
    extension_ids: Map([]),
    extension_namespaces: Map([]),
    apis: Map([]),
    api_names: Map([]),
    destroy_hooks: Map([]),
    op_registry: OpRegistry::new(),
  }
}

///|
/// Installs an extension into the host.
pub fn ExtensionHost::install(
  self : ExtensionHost,
  extension : Extension,
) -> Unit raise {
  guard extension.id.trim().to_owned() != "" else { raise EmptyExtensionId }
  guard extension.js_namespace.trim().to_owned() != "" else {
    raise EmptyNamespace
  }
  guard !extension_namespace_is_reserved(extension.js_namespace) else {
    raise ReservedNamespace(extension_namespace=extension.js_namespace)
  }
  guard self.extension_ids.get(extension.id) is None else {
    raise DuplicateExtensionId(id=extension.id)
  }
  guard self.extension_namespaces.get(extension.js_namespace) is None else {
    raise DuplicateNamespace(extension_namespace=extension.js_namespace)
  }
  let context = ExtensionContext::{
    host: self,
    extension_id: extension.id,
    extension_namespace: extension.js_namespace,
  }
  self.extension_ids.set(extension.id, extension.js_namespace)
  self.extension_namespaces.set(extension.js_namespace, extension.id)
  self.destroy_hooks.set(extension.id, fn() raise {
    (extension.on_destroy)(context)
  })
  (extension.register)(context)
  (extension.on_install)(context)
}

///|
/// Validates and records an extension-scoped event.
pub fn[Payload : ToJson] ExtensionHost::emit(
  self : ExtensionHost,
  extension_namespace : String,
  event_name : String,
  payload : Payload,
) -> Unit raise ExtensionHostError {
  validate_extension_event_target(extension_namespace, event_name)
  guard self.extension_namespaces.get(extension_namespace) is Some(_) else {
    raise NamespaceNotInstalled(extension_namespace~)
  }
  ignore(ToJson::to_json(payload))
}

///|
/// Drops all registered extension metadata.
pub fn ExtensionHost::destroy(self : ExtensionHost) -> Unit raise {
  for _, hook in self.destroy_hooks {
    hook()
  }
  self.extension_ids.clear()
  self.extension_namespaces.clear()
  self.apis.clear()
  self.api_names.clear()
  self.destroy_hooks.clear()
}

///|
/// Reserves an API name for one extension namespace and returns its fully
/// qualified op name.
fn ExtensionContext::register_api(
  self : ExtensionContext,
  api_name : String,
) -> String raise ExtensionHostError {
  validate_extension_api_name(self.extension_namespace, api_name)
  let registry_key = extension_api_registry_key(
    self.extension_namespace,
    api_name,
  )
  guard self.host.apis.get(registry_key) is None else {
    raise DuplicateApi(extension_namespace=self.extension_namespace, api_name~)
  }
  self.host.apis.set(registry_key, true)
  match self.host.api_names.get(self.extension_namespace) {
    Some(names) => names.push(api_name)
    None => self.host.api_names.set(self.extension_namespace, [api_name])
  }
  extension_op_name(self.extension_namespace, api_name)
}

///|
/// Returns the API names registered for one installed extension namespace.
pub fn ExtensionHost::api_names(
  self : ExtensionHost,
  extension_namespace : String,
) -> Array[String] {
  match self.api_names.get(extension_namespace) {
    Some(names) => names.map(fn(name) { name })
    None => []
  }
}

///|
/// Dispatches one installed extension op with a raw JSON payload.
pub fn ExtensionHost::dispatch_op(
  self : ExtensionHost,
  name : String,
  payload : Json,
) -> Json raise OpDispatchError {
  self.op_registry.call(name, payload)
}

///|
/// Builds a unique registry key for one extension namespace and API pair.
fn extension_api_registry_key(
  extension_namespace : String,
  api_name : String,
) -> String {
  extension_namespace + "\u0000" + api_name
}

///|
/// Converts an extension namespace/API pair into the runtime op binding name.
fn extension_op_name(extension_namespace : String, api_name : String) -> String {
  "ext:" + extension_namespace + "/" + api_name
}

///|
fn validate_extension_api_name(
  extension_namespace : String,
  api_name : String,
) -> Unit raise ExtensionHostError {
  guard api_name.trim().to_owned() != "" else {
    raise EmptyApiName(extension_namespace~)
  }
  guard !extension_is_reserved_api_name(api_name) else {
    raise ReservedApiName(extension_namespace~, api_name~)
  }
}

///|
fn validate_extension_event_target(
  extension_namespace : String,
  event_name : String,
) -> Unit raise ExtensionHostError {
  guard extension_namespace.trim().to_owned() != "" else {
    raise EmptyEventNamespace
  }
  guard event_name.trim().to_owned() != "" else {
    raise EmptyEventName(extension_namespace~)
  }
}

///|
/// Rejects JavaScript property names that would be unsafe to expose on `window.__MoonBit__`.
fn extension_is_disallowed_js_property_name(name : String) -> Bool {
  name.has_prefix("@@") ||
  name == "__proto__" ||
  name == "prototype" ||
  name == "constructor"
}

///|
/// Returns whether an extension namespace is reserved.
fn extension_namespace_is_reserved(extension_namespace : String) -> Bool {
  extension_is_disallowed_js_property_name(extension_namespace)
}

///|
/// Returns whether an extension API name is reserved.
fn extension_is_reserved_api_name(api_name : String) -> Bool {
  extension_is_disallowed_js_property_name(api_name)
}
