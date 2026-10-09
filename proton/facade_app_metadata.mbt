///|
/// Returns package.product_name from the loaded configuration snapshot.
pub fn App::name(self : App) -> String raise AppConfigError {
  match self.loaded_config().package_config {
    Some(package_config) => package_config.product_name.trim().to_owned()
    None => raise @proton_config.MissingField(path="package.product_name")
  }
}

///|
/// Returns package.version from the loaded configuration snapshot.
pub fn App::version(self : App) -> String raise AppConfigError {
  match self.loaded_config().package_config {
    Some(package_config) => package_config.version.trim().to_owned()
    None => raise @proton_config.MissingField(path="package.version")
  }
}
