///|
priv struct DeclaredPlatformRequirement {
  archive : String
  sha256 : String
  supported : Bool
} derive(FromJson)

///|
priv struct DeclaredRuntimeRequirements {
  schema_version : Int
  layout_version : Int
  base_url : String
  platforms : Map[String, DeclaredPlatformRequirement]
} derive(FromJson)

///|
async fn read_declared_requirement(path : String) -> RuntimeRequirement {
  let content = @async_fs.read_file(path).text() catch {
    error =>
      raise CefRuntimeError::RequirementRead(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  let json = @json.parse(content) catch {
    error =>
      raise CefRuntimeError::RequirementSyntax(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  let declared : DeclaredRuntimeRequirements = @json.from_json(json) catch {
    error =>
      raise CefRuntimeError::RequirementInvalid(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard declared.schema_version == 1 else {
    raise CefRuntimeError::RequirementInvalid(
      path~,
      detail="unsupported schema_version " + declared.schema_version.to_string(),
    )
  }
  guard declared.layout_version > 0 && declared.base_url != "" else {
    raise CefRuntimeError::RequirementInvalid(
      path~,
      detail="layout_version and base_url are required",
    )
  }
  let platform = current_platform()
  guard declared.platforms.get(platform.id) is Some(selected) else {
    raise CefPlatformError::Unsupported(platform=platform.id)
  }
  guard selected.supported else {
    raise CefPlatformError::Unsupported(platform=platform.id)
  }
  guard selected.archive != "" && selected.sha256.length() == 64 else {
    raise CefRuntimeError::RequirementInvalid(
      path~,
      detail="invalid archive metadata for " + platform.id,
    )
  }
  RuntimeRequirement::{
    base_url: declared.base_url,
    platform: platform.id,
    cef_archive: selected.archive,
    cef_sha256: selected.sha256,
    layout_version: declared.layout_version,
  }
}
