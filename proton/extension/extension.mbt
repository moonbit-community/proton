///|
struct Extension {
  definition_id : UInt64
  contract : @proton_contract.ExtensionContract
  command_routes : Array[@proton_contract.ContractRoute]
  register : (@proton_command.CommandRegistrar) -> Unit raise
  scripts : Array[String]
  dependencies : Array[String]
  resolve_permission : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError
  event_source : EventSource?
  on_destroy : () -> Unit raise
}

///|
/// One event produced by an extension-owned native event source.
pub struct Event {
  extension_id : String
  extension_namespace : String
  name : String
  payload : Json
}

///|
/// A native event source integrated with Proton's host event loop.
///
/// `start` installs an opaque native wakeup before the source begins producing
/// events. Native callbacks enqueue their payload and invoke that wakeup;
/// Proton later calls `drain` on the runtime owner thread. `stop` must be
/// idempotent and wait until the source can no longer invoke the wakeup.
pub struct EventSource {
  start : (EventWakeup) -> Unit raise
  stop : () -> Unit
  drain : () -> Array[Event] raise
}

///|
/// The opaque native callback supplied to an extension event source.
pub type EventWakeup = @ffi.EventWakeup

///|
let next_extension_definition_id : Ref[UInt64] = Ref(0UL)

///|
fn allocate_extension_definition_id() -> UInt64 {
  next_extension_definition_id.val += 1UL
  next_extension_definition_id.val
}

///|
/// A typed extension capability that can be granted to a renderer.
///
/// Extension packages build this value after validating their public scope
/// types. Applications pass it to `App::capability` without handling extension
/// identifiers or raw permission JSON.
pub struct RendererCapability {
  extension : Extension
  scope : Json
}

///|
/// Builds an installable extension from typed command descriptors.
///
/// Validation is deferred until application configuration so invalid static
/// extension metadata follows the facade's ordinary adaptation error path.
pub fn typed(
  contract : @proton_contract.ExtensionContract,
  command_routes : Array[@proton_contract.ContractRoute],
  register : (@proton_command.CommandRegistrar) -> Unit raise,
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError = fn(
    scope,
    _base_path,
  ) -> Json raise @proton_command.PermissionScopeValidationError {
    guard scope is Object(fields) else {
      raise @proton_command.PermissionScopeValidationError::Invalid(
        detail="extension " +
          contract.id() +
          " permission scope must be an object",
      )
    }
    for _, _ in fields {
      raise @proton_command.PermissionScopeValidationError::Invalid(
        detail="extension " +
          contract.id() +
          " does not accept a non-empty permission scope",
      )
    }
    scope
  },
  event_source? : EventSource,
  on_destroy? : () -> Unit raise = fn() {  },
) -> Extension {
  Extension::{
    definition_id: allocate_extension_definition_id(),
    contract,
    command_routes: command_routes.map(route => route),
    register,
    scripts: scripts.map(script => script),
    dependencies: dependencies.map(dependency => dependency),
    resolve_permission,
    event_source,
    on_destroy,
  }
}

///|
/// Defines a wake-driven event source with explicit teardown.
pub fn event_source(
  start : (EventWakeup) -> Unit raise,
  stop : () -> Unit,
  drain : () -> Array[Event] raise,
) -> EventSource {
  EventSource::{ start, stop, drain, }
}

///|
/// Encodes a typed extension event for delivery to renderer subscribers.
pub fn[Payload : ToJson] event(
  descriptor : @proton_contract.Event[Payload],
  payload : Payload,
) -> Event raise @proton_contract.ContractDefinitionError {
  descriptor.validate()
  let route = descriptor.contract_route()
  guard route.extension_id() is Some(extension_id) &&
    route.extension_namespace() is Some(extension_namespace) else {
    raise @proton_contract.ContractDefinitionError::ExpectedExtensionEvent(
      route=route.operation_name(),
    )
  }
  Event::{
    extension_id,
    extension_namespace,
    name: descriptor.name(),
    payload: ToJson::to_json(payload),
  }
}

///|
/// Builds a renderer capability from an extension definition and its validated
/// internal scope.
///
/// This constructor is intended for extension authors. Application-facing
/// extension packages should expose a typed `capability` function instead.
pub fn capability(
  extension : Extension,
  scope? : Json = Json::empty_object(),
) -> RendererCapability {
  RendererCapability::{ extension, scope: clone_capability_json(scope), }
}

///|
#doc(hidden)
pub fn RendererCapability::id(self : RendererCapability) -> String {
  self.extension.id()
}

///|
#doc(hidden)
pub fn RendererCapability::command_spec(
  self : RendererCapability,
) -> @proton_command.AppCommandExtensionSpec raise ExtensionAdapterError {
  self.extension.command_spec()
}

///|
#doc(hidden)
pub fn RendererCapability::scope(self : RendererCapability) -> Json {
  clone_capability_json(self.scope)
}

///|
#doc(hidden)
pub fn RendererCapability::event_source(
  self : RendererCapability,
) -> EventSource? {
  self.extension.event_source
}

///|
#doc(hidden)
pub fn RendererCapability::definition_id(self : RendererCapability) -> UInt64 {
  self.extension.definition_id
}

///|
#doc(hidden)
pub fn EventSource::start(
  self : EventSource,
  wakeup : EventWakeup,
) -> Unit raise {
  (self.start)(wakeup)
}

///|
#doc(hidden)
pub fn EventSource::stop(self : EventSource) -> Unit {
  (self.stop)()
}

///|
#doc(hidden)
pub fn EventSource::drain(self : EventSource) -> Array[Event] raise {
  (self.drain)()
}

///|
#doc(hidden)
pub fn Event::extension_id(self : Event) -> String {
  self.extension_id
}

///|
#doc(hidden)
pub fn Event::extension_namespace(self : Event) -> String {
  self.extension_namespace
}

///|
#doc(hidden)
pub fn Event::name(self : Event) -> String {
  self.name
}

///|
#doc(hidden)
pub fn Event::payload(self : Event) -> Json {
  clone_capability_json(self.payload)
}

///|
pub fn Extension::id(self : Extension) -> String {
  self.contract.id()
}

///|
pub fn Extension::command_spec(
  self : Extension,
) -> @proton_command.AppCommandExtensionSpec raise ExtensionAdapterError {
  @proton_command.AppCommandExtensionSpec::typed(
    self.contract,
    self.command_routes,
    self.register,
    scripts=self.scripts,
    dependencies=self.dependencies,
    resolve_permission=self.resolve_permission,
    on_destroy=self.on_destroy,
  ) catch {
    error =>
      raise TypedSpecInvalid(
        extension_id=self.contract.id(),
        detail=error.message(),
      )
  }
}

///|
fn clone_capability_json(value : Json) -> Json {
  match value {
    Array(values) => Json::array(values.map(clone_capability_json))
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, value in fields {
        copied[key] = clone_capability_json(value)
      }
      Json::object(copied)
    }
    _ => value
  }
}
