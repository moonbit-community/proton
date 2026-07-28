///|
/// Converts the auto-launch package platform enum into a stable JS label.
fn platform_label(platform : @sys_auto_launch.Platform) -> String {
  match platform {
    Windows => "windows"
    Macos => "macos"
    Linux => "linux"
    Unsupported => "unsupported"
  }
}

///|
/// Builds one launcher from JavaScript payload data.
fn build_launcher(
  payload : @auto_launch_contract.AutoLaunchRequest,
) -> @sys_auto_launch.AutoLaunch raise AutoLaunchError {
  let launch_in_background = match payload.launch_in_background {
    Some(value) => value
    None => false
  }
  let background_arg = match payload.background_arg {
    Some(value) => value
    None => "--hidden"
  }
  let extra_arguments = match payload.extra_arguments {
    Some(value) => value
    None => []
  }
  let launcher = match (payload.path, payload.identifier) {
    (Some(path), Some(identifier)) =>
      @sys_auto_launch.new(
        payload.name,
        path~,
        launch_in_background~,
        background_arg~,
        extra_arguments~,
        identifier~,
      )
    (Some(path), None) =>
      @sys_auto_launch.new(
        payload.name,
        path~,
        launch_in_background~,
        background_arg~,
        extra_arguments~,
      )
    (None, Some(identifier)) =>
      @sys_auto_launch.new(
        payload.name,
        launch_in_background~,
        background_arg~,
        extra_arguments~,
        identifier~,
      )
    (None, None) =>
      @sys_auto_launch.new(
        payload.name,
        launch_in_background~,
        background_arg~,
        extra_arguments~,
      )
  }
  match launcher {
    Ok(launcher) => launcher
    Err(error) => raise InvalidConfiguration(detail=error.to_string())
  }
}

///|
/// Converts a launcher into the serializable descriptor used by JS.
fn launcher_reply(
  launcher : @sys_auto_launch.AutoLaunch,
) -> @auto_launch_contract.AutoLaunchReply {
  @auto_launch_contract.AutoLaunchReply::{
    name: launcher.name(),
    path: launcher.path(),
    identifier: launcher.identifier(),
  }
}

///|
fn auto_launch_support() -> @auto_launch_contract.SupportReply {
  @auto_launch_contract.SupportReply::{
    supported: @sys_auto_launch.is_supported(),
    platform: platform_label(@sys_auto_launch.current_platform()),
  }
}

///|
fn describe_auto_launch(
  payload : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.AutoLaunchReply raise AutoLaunchError {
  launcher_reply(build_launcher(payload))
}

///|
fn is_auto_launch_enabled(
  payload : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.EnabledReply raise AutoLaunchError {
  let launcher = build_launcher(payload)
  match launcher.is_enabled() {
    Ok(enabled) => @auto_launch_contract.EnabledReply::{ enabled, }
    Err(error) =>
      raise QueryFailed(
        identifier=launcher.identifier(),
        detail=error.to_string(),
      )
  }
}

///|
fn enable_auto_launch(
  payload : @auto_launch_contract.AutoLaunchRequest,
) -> String raise AutoLaunchError {
  let launcher = build_launcher(payload)
  match launcher.enable() {
    Ok(_) => launcher.identifier()
    Err(error) =>
      raise EnableFailed(
        identifier=launcher.identifier(),
        detail=error.to_string(),
      )
  }
}

///|
fn disable_auto_launch(
  payload : @auto_launch_contract.AutoLaunchRequest,
) -> String raise AutoLaunchError {
  let launcher = build_launcher(payload)
  match launcher.disable() {
    Ok(_) => launcher.identifier()
    Err(error) =>
      raise DisableFailed(
        identifier=launcher.identifier(),
        detail=error.to_string(),
      )
  }
}
