///|
test "auto launch current platform has a JavaScript label" {
  let label = platform_label(@sys_auto_launch.current_platform())
  assert_true(["windows", "macos", "linux", "unsupported"].contains(label))
}

///|
test "auto launch descriptor validates payloads through package constructor" {
  let error = try
    build_launcher(AutoLaunchPayload::{
      name: "",
      path: None,
      launch_in_background: None,
      background_arg: None,
      extra_arguments: None,
      identifier: None,
    })
  catch {
    error => error
  } noraise {
    _ => abort("expected empty name to be rejected")
  }
  assert_true(error.message().contains("EmptyName"))
}

///|
test "auto launch metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-auto-launch")
  let command_spec = extension().command_spec() catch {
    error => abort(error.message())
  }
  assert_eq(command_spec.unwrap().js_namespace(), "autoLaunch")
}
