///|
/// The opaque scope carried by a contract route.
#doc(hidden)
pub enum ContractScope {
  Application
  Extension(id~ : String, js_namespace~ : String)
}

///|
/// A request payload with no fields, shared by commands that take no input.
pub(all) struct EmptyRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend EmptyRequest with Eq::{not_equal, equal}

///|
pub extend EmptyRequest with Debug::{to_repr}

///|
pub extend EmptyRequest with ToJson::{to_json}

///|
pub extend EmptyRequest with FromJson::{from_json}

///|
/// Standard platform-support probe result, shared by extension `support` commands.
pub(all) struct SupportReply {
  supported : Bool
  platform : String
  reason : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SupportReply with Eq::{not_equal, equal}

///|
pub extend SupportReply with Debug::{to_repr}

///|
pub extend SupportReply with ToJson::{to_json}

///|
pub extend SupportReply with FromJson::{from_json}

///|
/// An opaque application or extension route carried by a typed descriptor.
///
/// Application code does not construct routes or assemble transport names
/// directly. Use `command`, `event`, or an `ExtensionContract`.
pub struct ContractRoute {
  scope : ContractScope
  name : String
}

///|
/// A target-neutral command descriptor.
///
/// The request and response parameters bind one stable command identity to its
/// payload types without storing serialization logic.
pub struct Command[Request, Response] {
  route : ContractRoute
  type_marker : ((Request) -> Response)?
}

///|
/// A target-neutral live-event descriptor.
///
/// Events are not replayed by the descriptor. Runtime integrations decide how
/// an event is emitted and subscribed. A route may be declared as an event only
/// once within its scope. Export and reuse that descriptor everywhere instead
/// of constructing another event with the same route, even with the same
/// payload type.
pub struct Event[Payload] {
  route : ContractRoute
  type_marker : ((Payload) -> Unit)?
  duplicate_route : Bool
}

///|
/// Process-global registry of declared event routes. Routes are expected to
/// be declared once at initialization; re-declaring the same route (after a
/// hot reload, or from two independent libraries) is rejected as
/// DuplicateEventRoute, and the map is intentionally not synchronized.
let declared_event_routes : Map[String, Unit] = Map([])

///|
/// The identity and route scope shared by one Proton extension contract.
pub struct ExtensionContract {
  id : String
  js_namespace : String
}

///|
/// Failures found while validating a contract descriptor before use.
pub(all) suberror ContractDefinitionError {
  EmptyApplicationName
  EmptyExtensionId
  EmptyExtensionNamespace
  EmptyExtensionMember(extension_namespace~ : String)
  DuplicateEventRoute(route~ : String)
} derive(Debug, Eq)

///|
pub extend ContractDefinitionError with Eq::{not_equal, equal}

///|
pub extend ContractDefinitionError with Debug::{to_repr}

///|
pub extend ContractDefinitionError with Show::{to_string, output}

///|
/// Creates an application command descriptor.
pub fn[Request, Response] command(name : String) -> Command[Request, Response] {
  Command::{ route: application_route(name), type_marker: None }
}

///|
/// Creates a unique application event descriptor.
///
/// Calling this function more than once with the same name is an invalid
/// contract declaration. Runtime values belong in the event payload, not in a
/// dynamically constructed event name.
pub fn[Payload] event(name : String) -> Event[Payload] {
  new_event(application_route(name))
}

///|
/// Creates the identity shared by an extension's command and event descriptors.
///
/// Extension packages normally expose a value generated from `proton.ext.json`
/// instead of calling this constructor by hand.
pub fn extension(id~ : String, js_namespace~ : String) -> ExtensionContract {
  ExtensionContract::{ id, js_namespace }
}

///|
/// Creates a typed command descriptor scoped to this extension.
pub fn[Request, Response] ExtensionContract::command(
  self : ExtensionContract,
  name : String,
) -> Command[Request, Response] {
  Command::{ route: self.route(name), type_marker: None }
}

///|
/// Creates a unique typed live-event descriptor scoped to this extension.
///
/// Calling this method more than once with the same member name on the same
/// extension contract is an invalid contract declaration. Runtime values
/// belong in the event payload, not in a dynamically constructed member name.
pub fn[Payload] ExtensionContract::event(
  self : ExtensionContract,
  name : String,
) -> Event[Payload] {
  new_event(self.route(name))
}

///|
/// Returns this extension contract's stable catalog identity.
pub fn ExtensionContract::id(self : ExtensionContract) -> String {
  self.id
}

///|
/// Returns this extension contract's JavaScript and transport namespace.
pub fn ExtensionContract::js_namespace(self : ExtensionContract) -> String {
  self.js_namespace
}

///|
/// Returns a command's stable member name without a transport prefix.
pub fn[Request, Response] Command::name(
  self : Command[Request, Response],
) -> String {
  self.route.name
}

///|
/// Returns an event's stable member name without a transport prefix.
pub fn[Payload] Event::name(self : Event[Payload]) -> String {
  self.route.name
}

///|
/// Validates a command descriptor before registration or invocation.
pub fn[Request, Response] Command::validate(
  self : Command[Request, Response],
) -> Unit raise ContractDefinitionError {
  self.route.validate()
}

///|
/// Validates an event descriptor before subscription or emission.
pub fn[Payload] Event::validate(
  self : Event[Payload],
) -> Unit raise ContractDefinitionError {
  self.route.validate()
  guard !self.duplicate_route else {
    raise DuplicateEventRoute(route=self.route.operation_name())
  }
}

///|
/// Validates the extension identity before it is installed or used.
pub fn ExtensionContract::validate(
  self : ExtensionContract,
) -> Unit raise ContractDefinitionError {
  guard self.id.trim().to_owned() != "" else { raise EmptyExtensionId }
  guard self.js_namespace.trim().to_owned() != "" else {
    raise EmptyExtensionNamespace
  }
}

///|
/// Returns the opaque route used by framework integrations.
#doc(hidden)
pub fn[Request, Response] Command::contract_route(
  self : Command[Request, Response],
) -> ContractRoute {
  self.route
}

///|
/// Returns the opaque route used by framework integrations.
#doc(hidden)
pub fn[Payload] Event::contract_route(self : Event[Payload]) -> ContractRoute {
  self.route
}

///|
/// Returns the internal operation name consumed by the bridge transport.
#doc(hidden)
pub fn ContractRoute::operation_name(self : ContractRoute) -> String {
  match self.scope {
    Application => "app:" + self.name
    Extension(js_namespace~, ..) => "ext:" + js_namespace + "/" + self.name
  }
}

///|
/// Returns the stable member name carried by this route.
#doc(hidden)
pub fn ContractRoute::member_name(self : ContractRoute) -> String {
  self.name
}

///|
/// Returns whether this route belongs to the application contract.
#doc(hidden)
pub fn ContractRoute::is_application(self : ContractRoute) -> Bool {
  self.scope is Application
}

///|
/// Returns the extension catalog identity for an extension route.
#doc(hidden)
pub fn ContractRoute::extension_id(self : ContractRoute) -> String? {
  match self.scope {
    Application => None
    Extension(id~, ..) => Some(id)
  }
}

///|
/// Returns the extension namespace for an extension route.
#doc(hidden)
pub fn ContractRoute::extension_namespace(self : ContractRoute) -> String? {
  match self.scope {
    Application => None
    Extension(js_namespace~, ..) => Some(js_namespace)
  }
}

///|
fn application_route(name : String) -> ContractRoute {
  ContractRoute::{ scope: Application, name }
}

///|
fn[Payload] new_event(route : ContractRoute) -> Event[Payload] {
  let operation_name = route.operation_name()
  let duplicate_route = declared_event_routes.contains(operation_name)
  if !duplicate_route {
    declared_event_routes[operation_name] = ()
  }
  Event::{ route, type_marker: None, duplicate_route }
}

///|
fn ExtensionContract::route(
  self : ExtensionContract,
  name : String,
) -> ContractRoute {
  ContractRoute::{
    scope: Extension(id=self.id, js_namespace=self.js_namespace),
    name,
  }
}

///|
fn ContractRoute::validate(
  self : ContractRoute,
) -> Unit raise ContractDefinitionError {
  match self.scope {
    Application => {
      guard self.name.trim().to_owned() != "" else {
        raise EmptyApplicationName
      }
    }
    Extension(id~, js_namespace~) => {
      guard id.trim().to_owned() != "" else { raise EmptyExtensionId }
      guard js_namespace.trim().to_owned() != "" else {
        raise EmptyExtensionNamespace
      }
      guard self.name.trim().to_owned() != "" else {
        raise EmptyExtensionMember(extension_namespace=js_namespace)
      }
    }
  }
}

///|
pub fn ContractDefinitionError::message(
  self : ContractDefinitionError,
) -> String {
  match self {
    EmptyApplicationName => "application contract name must not be empty"
    EmptyExtensionId => "extension contract id must not be empty"
    EmptyExtensionNamespace => "extension contract namespace must not be empty"
    EmptyExtensionMember(extension_namespace~) =>
      "extension contract member must not be empty: " + extension_namespace
    DuplicateEventRoute(route~) =>
      "event route is declared more than once: " + route
  }
}

///|
impl Show for ContractDefinitionError with fn output(self, logger) {
  logger.write_string(self.message())
}
