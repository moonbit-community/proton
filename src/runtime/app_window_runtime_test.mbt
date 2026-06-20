///|
fn app_window_cef_unit_tests_enabled() -> Bool {
  match @sys.get_env_var("PROTON_RUN_CEF_UNIT_TESTS") {
    Some("1") => @webview.backend_available()
    _ => false
  }
}

///|
test "App registers additional windows before run" {
  guard app_window_cef_unit_tests_enabled() else { return }
  let config = @runtime.AppConfig::new(
    @runtime.WindowConfig::new("runtime-main", 800, 600),
    @runtime.AppEntry::Html("<html>Main</html>"),
    windows=[
      @runtime.AppWindowConfig::new(
        "docs",
        @runtime.WindowConfig::new("Docs", 640, 480),
        @runtime.AppEntry::Html("<html>Docs</html>"),
      ),
    ],
  )
  let app = @runtime.App::new(config)
  assert_eq(app.main_window().id(), "main")
  assert_eq(app.windows().length(), 2)
  match app.window("docs") {
    Some(window) => {
      assert_eq(window.id(), "docs")
      assert_eq(window.config().title, "Docs")
    }
    None => abort("expected docs window")
  }
  app.destroy()
}

///|
test "AppConfig and App accessors expose window snapshots" {
  guard app_window_cef_unit_tests_enabled() else { return }
  let configured_windows = [
    @runtime.AppWindowConfig::new(
      "docs",
      @runtime.WindowConfig::new("Docs", 640, 480),
      @runtime.AppEntry::Html("<html>Docs</html>"),
    ),
  ]
  let config = @runtime.AppConfig::new(
    @runtime.WindowConfig::new("runtime-main", 800, 600),
    @runtime.AppEntry::Html("<html>Main</html>"),
    windows=configured_windows,
  )
  configured_windows.push(
    @runtime.AppWindowConfig::new(
      "late",
      @runtime.WindowConfig::new("Late", 320, 240),
      @runtime.AppEntry::Html("<html>Late</html>"),
    ),
  )

  let app = @runtime.App::new(config)
  config.windows.push(
    @runtime.AppWindowConfig::new(
      "external",
      @runtime.WindowConfig::new("External", 320, 240),
      @runtime.AppEntry::Html("<html>External</html>"),
    ),
  )
  assert_eq(app.windows().length(), 2)
  assert_eq(app.config().windows.length(), 1)

  let snapshot = app.windows()
  snapshot.push(app.main_window())
  assert_eq(app.windows().length(), 2)

  let config_snapshot = app.config()
  config_snapshot.windows.push(
    @runtime.AppWindowConfig::new(
      "mutated",
      @runtime.WindowConfig::new("Mutated", 320, 240),
      @runtime.AppEntry::Html("<html>Mutated</html>"),
    ),
  )
  assert_eq(app.config().windows.length(), 1)
  app.destroy()
}

///|
test "App::install_extension_spec builds one extension instance per window" {
  guard app_window_cef_unit_tests_enabled() else { return }
  let mut build_count = 0
  let config = @runtime.AppConfig::new(
    @runtime.WindowConfig::new("runtime-main", 800, 600),
    @runtime.AppEntry::Html("<html>Main</html>"),
    windows=[
      @runtime.AppWindowConfig::new(
        "docs",
        @runtime.WindowConfig::new("Docs", 640, 480),
        @runtime.AppEntry::Html("<html>Docs</html>"),
      ),
    ],
  )
  let app = @runtime.App::new(config)
  let spec = @core.ExtensionSpec::new("tests/fresh", "fresh", fn(_context) {
    build_count += 1
    Ok(@core.Extension::new("tests/fresh", "fresh", fn(_extension) {  }))
  })
  match app.install_extension_spec(spec, @core.ExtensionBuildContext::new()) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  assert_eq(build_count, 2)
  let _ = app.create_window(
    @runtime.AppWindowConfig::new(
      "later",
      @runtime.WindowConfig::new("Later", 480, 320),
      @runtime.AppEntry::Html("<html>Later</html>"),
    ),
  )
  assert_eq(build_count, 3)
  app.destroy()
}

///|
test "panic App::install_extension applies to registered windows" {
  guard app_window_cef_unit_tests_enabled() else { return }
  let config = @runtime.AppConfig::new(
    @runtime.WindowConfig::new("runtime-main", 800, 600),
    @runtime.AppEntry::Html("<html>Main</html>"),
    windows=[
      @runtime.AppWindowConfig::new(
        "docs",
        @runtime.WindowConfig::new("Docs", 640, 480),
        @runtime.AppEntry::Html("<html>Docs</html>"),
      ),
    ],
  )
  let app = @runtime.App::new(config)
  app.install_extension(
    @core.Extension::new("tests/math", "math", fn(_extension) {  }),
  )
  match app.window("docs") {
    Some(window) =>
      @core.install_extension(
        window.webview(),
        @core.Extension::new("tests/math", "math", fn(_extension) {  }),
      )
    None => abort("expected docs window")
  }
}
