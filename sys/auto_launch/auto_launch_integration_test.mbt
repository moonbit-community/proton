///|
/// Returns whether `value` should enable integration-test execution.
fn is_truthy_env_value(value : String?) -> Bool {
  match value {
    Some("1") => true
    Some("true") => true
    Some("yes") => true
    Some("on") => true
    _ => false
  }
}

///|
/// Reads the integration-test toggle from the process environment.
fn integration_tests_enabled() -> Bool {
  is_truthy_env_value(
    @env.get_env_var("MOONBIT_AUTO_LAUNCH_RUN_INTEGRATION_TESTS"),
  )
}

///|
/// Returns a safe, platform-specific executable path for integration tests.
fn stable_test_path(platform : Platform) -> String {
  match platform {
    Platform::Windows => "C:\\Windows\\System32\\notepad.exe"
    Platform::Macos => "/usr/bin/true"
    Platform::Linux => "/bin/true"
    Platform::Unsupported => "/unsupported"
  }
}

///|
/// Builds the launcher instance shared by the integration roundtrip test.
fn new_integration_test_launcher() -> Result[AutoLaunch, AutoLaunchError] {
  let platform = @proton_auto_launch.current_platform()
  @proton_auto_launch.new(
    "MoonBit Auto Launch Integration Test",
    path=stable_test_path(platform),
    identifier="moonbit-auto-launch-integration-test",
  )
}

///|
/// Verifies the real backend can enable, query, and disable one launcher entry.
test "integration enable disable roundtrip" {
  guard integration_tests_enabled() else { return }
  guard @proton_auto_launch.is_supported() else {
    fail("integration tests were enabled on an unsupported platform")
  }

  let launcher = match new_integration_test_launcher() {
    Ok(value) => value
    Err(error) => fail("failed to build launcher: \{error}")
  }

  ignore(launcher.disable())

  match launcher.is_enabled() {
    Ok(false) => ()
    Ok(true) => fail("launcher should be disabled after cleanup")
    Err(error) => fail("failed to query initial auto-launch state: \{error}")
  }

  match launcher.enable() {
    Ok(_) => ()
    Err(error) => fail("failed to enable auto-launch: \{error}")
  }

  match launcher.is_enabled() {
    Ok(true) => ()
    Ok(false) => fail("launcher should be enabled after enable()")
    Err(error) => fail("failed to query enabled auto-launch state: \{error}")
  }

  match launcher.disable() {
    Ok(_) => ()
    Err(error) => fail("failed to disable auto-launch: \{error}")
  }

  match launcher.is_enabled() {
    Ok(false) => ()
    Ok(true) => fail("launcher should be disabled after disable()")
    Err(error) => fail("failed to query disabled auto-launch state: \{error}")
  }
}
