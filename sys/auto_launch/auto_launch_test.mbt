///|
/// Verifies that the public library symbols remain available to downstream callers.
test "public api symbols are exported" {
  ignore(@auto_launch.current_platform)
  ignore(@auto_launch.is_supported)
  ignore(@auto_launch.AutoLaunch::name)
  ignore(@auto_launch.AutoLaunch::path)
  ignore(@auto_launch.AutoLaunch::identifier)
  ignore(@auto_launch.AutoLaunch::enable)
  ignore(@auto_launch.AutoLaunch::disable)
  ignore(@auto_launch.AutoLaunch::is_enabled)
}

///|
/// Returns a stable sample executable path for public API tests on `platform`.
fn sample_public_app_path(platform : Platform) -> String {
  match platform {
    Windows => "C:\\Program Files\\MoonBit\\moonbit.exe"
    Macos => "/Applications/MoonBit.app/Contents/MacOS/MoonBit"
    Linux => "/usr/bin/moonbit"
    Unsupported => "/unsupported"
  }
}

///|
/// Builds a launcher with predictable defaults for black-box API tests.
fn new_public_test_launcher(
  identifier : String,
  name? : String = "MoonBit Auto Launch",
  path? : String,
  launch_in_background? : Bool = false,
  extra_arguments? : Array[String] = [],
) -> Result[AutoLaunch, AutoLaunchError] {
  let platform = @auto_launch.current_platform()
  let resolved_path = match path {
    Some(value) => value
    None => sample_public_app_path(platform)
  }
  @auto_launch.new(
    name,
    path=resolved_path,
    launch_in_background~,
    extra_arguments~,
    identifier~,
  )
}

///|
/// Ensures the public constructor rejects empty application names.
test "new validates empty names" {
  match @auto_launch.new("") {
    Err(EmptyName) => ()
    _ => fail("expected EmptyName")
  }
  match @auto_launch.new("   ") {
    Err(EmptyName) => ()
    _ => fail("expected EmptyName")
  }
}

///|
/// Ensures the public constructor rejects relative explicit executable paths.
test "new validates relative explicit paths" {
  match @auto_launch.new("Auto Launch", path="relative/path") {
    Err(RelativeExecutablePath(path)) => assert_eq(path, "relative/path")
    _ => fail("expected RelativeExecutablePath")
  }
}

///|
/// Ensures launcher creation succeeds on supported platforms with valid input.
test "new creates a launcher on supported platforms" {
  guard @auto_launch.is_supported() else { return }

  let launcher = match
    new_public_test_launcher("moonbit-auto-launch", launch_in_background=true, extra_arguments=[
      "--verbose",
    ]) {
    Ok(value) => value
    Err(error) => fail("expected launcher creation to succeed: \{error}")
  }

  assert_eq(launcher.name(), "MoonBit Auto Launch")
  assert_eq(launcher.identifier(), "moonbit-auto-launch")
}

///|
/// Ensures runtime platform detection and support reporting stay consistent.
test "current platform and support flag stay in sync" {
  match (@auto_launch.current_platform(), @auto_launch.is_supported()) {
    (Unsupported, false) => ()
    (Windows, true) => ()
    (Macos, true) => ()
    (Linux, true) => ()
    _ => fail("platform support detection should stay consistent")
  }
}

///|
/// Exercises the public enable-disable roundtrip on Windows startup entries.
test "public methods can roundtrip a windows startup entry" {
  guard @auto_launch.current_platform() is Windows else { return }

  let launcher = match
    new_public_test_launcher(
      "moonbit-auto-launch-public-roundtrip-test",
      name="MoonBit Auto Launch Public Roundtrip Test",
      path="C:\\Windows\\System32\\notepad.exe",
    ) {
    Ok(value) => value
    Err(error) => fail("expected launcher creation to succeed: \{error}")
  }

  ignore(launcher.disable())

  match launcher.enable() {
    Ok(_) => ()
    Err(error) => fail("failed to enable auto-launch: \{error}")
  }

  match launcher.is_enabled() {
    Ok(true) => ()
    Ok(false) => fail("launcher should be enabled after enable()")
    Err(error) => fail("failed to query enabled state: \{error}")
  }

  match launcher.disable() {
    Ok(_) => ()
    Err(error) => fail("failed to disable auto-launch: \{error}")
  }

  match launcher.is_enabled() {
    Ok(false) => ()
    Ok(true) => fail("launcher should be disabled after disable()")
    Err(error) => fail("failed to query disabled state: \{error}")
  }
}
