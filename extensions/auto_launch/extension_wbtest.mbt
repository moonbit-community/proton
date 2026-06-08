///|
test "auto launch current platform has a JavaScript label" {
  let label = platform_label(@sys_auto_launch.current_platform())
  assert_true(["windows", "macos", "linux", "unsupported"].contains(label))
}

///|
test "auto launch descriptor validates payloads through package constructor" {
  match
    build_launcher(AutoLaunchPayload::{
      name: "",
      path: None,
      launch_in_background: None,
      background_arg: None,
      extra_arguments: None,
      identifier: None,
    }) {
    Err(error) => assert_true(error.contains("EmptyName"))
    Ok(_) => fail("expected empty name to be rejected")
  }
}

///|
test "auto launch metadata constants match generated app command extension" {
  assert_eq(
    generated_app_command_extension().id(),
    "justjavac/lepus-auto-launch",
  )
  assert_eq(generated_app_command_extension().js_namespace(), "autoLaunch")
}
