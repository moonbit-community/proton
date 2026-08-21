///|
let runtime_manifest_name = "manifest.json"

///|
priv struct RuntimeManifest {
  schema_version : Int
  platform : String
  cef_archive : String
  cef_sha256 : String
  layout_version : Int
  sdk : String
  runtime : String
} derive(ToJson, FromJson, Eq)

///|
extend RuntimeManifest with ToJson::{to_json}

///|
pub struct InstalledRuntime {
  root : String
  sdk_root : String
  runtime_root : String
  platform : String
  cef_archive : String
  cef_sha256 : String
  layout_version : Int
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
pub fn InstalledRuntime::platform(self : InstalledRuntime) -> String {
  self.platform
}

///|
pub fn InstalledRuntime::cef_archive(self : InstalledRuntime) -> String {
  self.cef_archive
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
    platform: requirement.platform,
    cef_archive: requirement.cef_archive,
    cef_sha256: requirement.cef_sha256,
    layout_version: requirement.layout_version,
  }
}

///|
fn installed_requirement(runtime : InstalledRuntime) -> RuntimeRequirement {
  {
    base_url: "",
    platform: runtime.platform,
    cef_archive: runtime.cef_archive,
    cef_sha256: runtime.cef_sha256,
    layout_version: runtime.layout_version,
  }
}

///|
fn runtime_manifest(requirement : RuntimeRequirement) -> RuntimeManifest {
  {
    schema_version: 1,
    platform: requirement.platform,
    cef_archive: requirement.cef_archive,
    cef_sha256: requirement.cef_sha256,
    layout_version: requirement.layout_version,
    sdk: "sdk",
    runtime: "runtime",
  }
}

///|
async fn read_runtime_manifest_json(path : String) -> Json {
  let content = @async_fs.read_file(path).text() catch {
    err =>
      raise CefRuntimeError::ManifestRead(
        path~,
        detail=@debug.render(Repr(err)),
      )
  }
  @json.parse(content) catch {
    err =>
      raise CefRuntimeError::ManifestSyntax(
        path~,
        detail=@debug.render(Repr(err)),
      )
  }
}

///|
async fn write_runtime_manifest(runtime : InstalledRuntime) -> Unit {
  let path = path_join(runtime.root, runtime_manifest_name)
  @async_fs.write_file(
    path,
    runtime_manifest(installed_requirement(runtime)).to_json().stringify() +
    "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Write(path~, detail=@debug.render(Repr(err)))
  }
}

///|
async fn validate_runtime_manifest(runtime : InstalledRuntime) -> Unit {
  let path = path_join(runtime.root, runtime_manifest_name)
  let actual : RuntimeManifest = @json.from_json(
    read_runtime_manifest_json(path),
  ) catch {
    error =>
      raise CefRuntimeError::ManifestInvalid(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  let expected = runtime_manifest(installed_requirement(runtime))
  guard actual == expected else {
    raise CefRuntimeError::ManifestInvalid(
      path~,
      detail="contents do not match the required CEF installation",
    )
  }
}
