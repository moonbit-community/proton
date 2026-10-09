///|
test "project files require portable relative paths" {
  for path in ["/tmp/backend", "frontend\\src", "C:/frontend"] {
    let config = @proton_config.AppConfig(
      "com.example.paths",
      backend=Some(@proton_config.BackendConfig(path, "app")),
    )
    try validate_project_paths(config) catch {
      @proton_config.InvalidField(..) => ()
      _ => fail("expected invalid project path")
    } noraise {
      _ => fail("expected project path validation to fail")
    }
  }
  validate_project_paths(
    @proton_config.AppConfig(
      "com.example.paths",
      frontend=Some(
        @proton_config.FrontendConfig(
          path=Some("../frontend"),
          dist=Some("dist"),
        ),
      ),
    ),
  )
}
