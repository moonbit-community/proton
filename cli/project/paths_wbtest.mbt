///|
async test "loading preserves path spelling without requiring referenced files" {
  let root = @fs.tmpdir(prefix="proton-project-paths-")
  defer @fs.rmdir(root, recursive=true)
  let source = @fsutil.path_join(root, "proton.project.json")
  for
    path in [
      @fsutil.path_join(root, "not-created"),
      "C:\\external\\assets",
      "\\\\server\\share\\assets",
      "../frontend",
      "assets\\icon.png",
    ] {
    let config = @proton_config.AppConfig(
      "com.example.paths",
      backend=Some(@proton_config.BackendConfig(path, "app")),
      frontend=Some(
        @proton_config.FrontendConfig(path=Some(path), dist=Some(path)),
      ),
      package_config=Some(
        @proton_config.PackageConfig(
          "Paths",
          "1.0.0",
          icons=[path],
          resources=[path],
          output=path,
          sign=Some(@proton_config.SignConfig(binaries=[path])),
          platforms=@proton_config.PackagePlatforms(
            windows=@proton_config.PlatformPackageConfig(
              resources=[path],
              sign=@proton_config.SignConfig(binaries=[path]),
            ),
          ),
        ),
      ),
    )
    @fs.write_file(
      source,
      config.to_json().stringify(),
      create_mode=CreateOrTruncate,
    )
    let project = load(source)
    assert_eq(project.base_dir, root)
    assert_eq(project.config, config)
  }
}
