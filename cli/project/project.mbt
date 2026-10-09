///|
/// A configuration and its source directory. Path values are preserved as written.
pub(all) struct Project {
  base_dir : String
  config : @proton_config.AppConfig
}

///|
/// Loads project configuration using the same decoder as the application.
pub async fn load(path : String) -> Project raise @proton_config.AppConfigError {
  let source = @fs.read_file(path).text() catch {
    error =>
      raise @proton_config.FileRead(path~, detail=@debug.render(Repr(error)))
  }
  let config = @proton_config.AppConfig::parse(source, name=path)
  { base_dir: @fsutil.path_parent(path), config, }
}
