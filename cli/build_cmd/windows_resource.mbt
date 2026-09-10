///|
priv struct WindowsAppResource {
  icon : String
  output_dir : String
} derive(ToJson)

///|
fn windows_app_resource(
  windows : Bool,
  config : @proton_config.ProjectConfig,
  icons : Array[String]?,
  target_dir : String?,
) -> WindowsAppResource? {
  guard windows else { return None }
  let icons = icons.unwrap_or_else(() => {
    config
    .package_config()
    .map(package_config => package_config.icons())
    .unwrap_or([])
  })
  for icon in icons {
    if icon.to_lower().has_suffix(".ico") {
      let root = @fsutil.resolve_path(config.base_dir(), ".")
      let output = target_dir.unwrap_or_else(() => {
        @fsutil.path_join(root, "target")
      })
      return Some({
        icon: @fsutil.resolve_path(root, icon),
        output_dir: @fsutil.path_join(output, "proton/windows-resources"),
      })
    }
  }
  None
}

///|
async fn app_build_process_env(
  resource : WindowsAppResource?,
) -> Map[String, String] noraise {
  let env = native_moon_process_env()
  // Explicit JSON null prevents a parent build request from leaking into a
  // different application or surviving removal of package.icons.
  env["PROTON_WINDOWS_APP_RESOURCE"] = resource
    .map(value => ToJson::to_json(value).stringify())
    .unwrap_or("null")
  env
}
