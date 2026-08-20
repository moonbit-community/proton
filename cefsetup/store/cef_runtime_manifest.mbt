///|
let runtime_manifest_name = "manifest.json"

///|
pub struct InstalledRuntime {
  root : String
  sdk_root : String
  runtime_root : String
  requirement : RuntimeRequirement
} derive(Debug, Eq)

///|
pub extend InstalledRuntime with Eq::{not_equal, equal}

///|
pub extend InstalledRuntime with Debug::{to_repr}

///|
pub fn InstalledRuntime::root(self : InstalledRuntime) -> String {
  self.root
}

///|
pub fn InstalledRuntime::sdk_root(self : InstalledRuntime) -> String {
  self.sdk_root
}

///|
pub fn InstalledRuntime::runtime_root(self : InstalledRuntime) -> String {
  self.runtime_root
}

///|
pub fn InstalledRuntime::requirement(
  self : InstalledRuntime,
) -> RuntimeRequirement {
  self.requirement
}

///|
fn installation_root(
  store_root : String,
  requirement : RuntimeRequirement,
) -> String {
  path_join(
    path_join(store_root, requirement.platform),
    cef_runtime_id(requirement.cef_sha256),
  )
}

///|
fn installed_runtime(
  store_root : String,
  requirement : RuntimeRequirement,
) -> InstalledRuntime {
  let root = installation_root(store_root, requirement)
  InstalledRuntime::{
    root,
    sdk_root: path_join(root, "sdk"),
    runtime_root: path_join(root, "runtime"),
    requirement,
  }
}

///|
fn runtime_manifest_json(requirement : RuntimeRequirement) -> String {
  Json::object({
    "schema_version": Json::number(1.0, repr="1"),
    "platform": requirement.platform,
    "cef_archive": requirement.cef_archive,
    "cef_sha256": requirement.cef_sha256,
    "layout_version": Json::number(
      requirement.layout_version.to_double(),
      repr=requirement.layout_version.to_string(),
    ),
    "sdk": "sdk",
    "runtime": "runtime",
  }).stringify()
}

///|
async fn write_runtime_manifest(runtime : InstalledRuntime) -> Unit {
  let path = path_join(runtime.root, runtime_manifest_name)
  @async_fs.write_file(
    path,
    runtime_manifest_json(runtime.requirement) + "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Write(path~, detail=@debug.render(Repr(err)))
  }
}

///|
fn require_manifest_string(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> String raise CefRuntimeError {
  match fields.get(name) {
    Some(String(value)) => value
    _ => raise CefRuntimeError::ManifestField(path~, field=name)
  }
}

///|
fn require_manifest_int(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> Int raise CefRuntimeError {
  match fields.get(name) {
    Some(value) =>
      @json.from_json(value) catch {
        _ => raise CefRuntimeError::ManifestField(path~, field=name)
      }
    None => raise CefRuntimeError::ManifestField(path~, field=name)
  }
}

///|
async fn validate_runtime_manifest(runtime : InstalledRuntime) -> Unit {
  let path = path_join(runtime.root, runtime_manifest_name)
  let json = read_json_file(path)
  guard json is Object(fields) else {
    raise CefRuntimeError::ManifestShape(path~, detail="root must be an object")
  }
  let schema_version = require_manifest_int(fields, "schema_version", path)
  guard schema_version == 1 else {
    raise CefRuntimeError::ManifestFieldValue(
      path~,
      field="schema_version",
      detail="expected 1, got " + schema_version.to_string(),
    )
  }
  let expected = runtime.requirement
  let values = [
    ("platform", expected.platform),
    ("cef_archive", expected.cef_archive),
    ("cef_sha256", expected.cef_sha256),
    ("sdk", "sdk"),
    ("runtime", "runtime"),
  ]
  for item in values {
    let (field, expected_value) = item
    let actual = require_manifest_string(fields, field, path)
    guard actual == expected_value else {
      raise CefRuntimeError::ManifestFieldValue(
        path~,
        field~,
        detail="expected \"" + expected_value + "\", got \"" + actual + "\"",
      )
    }
  }
  let layout_version = require_manifest_int(fields, "layout_version", path)
  guard layout_version == expected.layout_version else {
    raise CefRuntimeError::ManifestFieldValue(
      path~,
      field="layout_version",
      detail="expected " +
        expected.layout_version.to_string() +
        ", got " +
        layout_version.to_string(),
    )
  }
}
