///|
/// One explicit import-time input needed to link an extension into an app project.
pub struct ExtensionLinkInput {
  id : String
  moonbit_import_path : String
} derive(Eq, Debug)

///|
/// Deterministic set of link inputs for a selected extension subset.
pub struct ExtensionLinkPlan {
  ordered_inputs : Array[ExtensionLinkInput]
} derive(Eq, Debug)

///|
/// Returns the ordered link inputs that should become explicit project edits.
/// Each input corresponds to one package import plus one registry registration
/// call in generated code.
pub fn ExtensionLinkPlan::inputs(
  self : ExtensionLinkPlan,
) -> Array[ExtensionLinkInput] {
  copy_link_inputs(self.ordered_inputs)
}

///|
/// Returns the extension ids in link order.
/// Transitive dependencies appear before the extensions that require them.
pub fn ExtensionLinkPlan::extension_ids(
  self : ExtensionLinkPlan,
) -> Array[String] {
  let ids : Array[String] = []
  for input in self.ordered_inputs {
    ids.push(input.id)
  }
  ids
}

///|
/// Returns the MoonBit import path needed to link this extension.
pub fn ExtensionLinkInput::moonbit_import_path(
  self : ExtensionLinkInput,
) -> String {
  self.moonbit_import_path
}

///|
/// Returns the extension id represented by this input.
/// This is the same id used by manifests and catalogs during planning.
pub fn ExtensionLinkInput::id(self : ExtensionLinkInput) -> String {
  self.id
}

///|
/// Builds a deterministic link plan from selected extension ids and metadata deps.
/// The plan expands transitive dependencies and rejects missing ids or cycles
/// with catalog-style diagnostics.
pub fn build_extension_link_plan(
  catalog : ExtensionCatalog,
  selected_ids : Array[String],
) -> ExtensionLinkPlan raise ExtensionLinkError {
  let visit_state : Map[String, Int] = Map([])
  let inputs : Array[ExtensionLinkInput] = []
  for id in selected_ids {
    let normalized = normalize_selected_extension_id(id)
    visit_linked_extension(normalized, None, catalog, visit_state, inputs)
  }
  ExtensionLinkPlan::{ ordered_inputs: copy_link_inputs(inputs) }
}

///|
/// Visits one extension id and appends it after all metadata dependencies.
fn visit_linked_extension(
  id : String,
  requested_by : String?,
  catalog : ExtensionCatalog,
  visit_state : Map[String, Int],
  inputs : Array[ExtensionLinkInput],
) -> Unit raise ExtensionLinkError {
  match visit_state.get(id) {
    Some(2) => return
    Some(1) => raise DependencyCycle(id~)
    _ => ()
  }

  let descriptor = require_linked_descriptor(id, requested_by, catalog)

  visit_state.set(id, 1)
  visit_linked_dependencies(
    id,
    descriptor.dependencies(),
    catalog,
    visit_state,
    inputs,
  )
  visit_state.set(id, 2)
  inputs.push(ExtensionLinkInput::{
    id,
    moonbit_import_path: descriptor.moonbit_import_path(),
  })
}

///|
/// Rejects blank selected extension ids before dependency resolution starts.
fn normalize_selected_extension_id(
  id : String,
) -> String raise ExtensionLinkError {
  let normalized = id.trim().to_owned()
  if normalized == "" {
    raise EmptySelectedId
  } else {
    normalized
  }
}

///|
/// Resolves one descriptor by id while preserving dependency context in errors.
fn require_linked_descriptor(
  id : String,
  requested_by : String?,
  catalog : ExtensionCatalog,
) -> ExtensionDescriptor raise ExtensionLinkError {
  match catalog.get(id) {
    Some(descriptor) => descriptor
    None =>
      match requested_by {
        Some(requested_by) =>
          raise MissingDependency(extension_id=requested_by, dependency_id=id)
        None => raise UnknownExtension(id~)
      }
  }
}

///|
/// Visits every dependency of one linked descriptor before recording it.
fn visit_linked_dependencies(
  id : String,
  dependencies : Array[String],
  catalog : ExtensionCatalog,
  visit_state : Map[String, Int],
  inputs : Array[ExtensionLinkInput],
) -> Unit raise ExtensionLinkError {
  for dependency in dependencies {
    visit_linked_extension(dependency, Some(id), catalog, visit_state, inputs)
  }
}
