///|
struct AutoLaunchPayload {
  name : String
  path : String?
  launch_in_background : Bool?
  background_arg : String?
  extra_arguments : Array[String]?
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct SupportReply {
  supported : Bool
  platform : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct AutoLaunchReply {
  name : String
  path : String
  identifier : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct EnabledReply {
  enabled : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MutationReply {
  changed : Bool
} derive(ToJson, FromJson, Debug, Eq)

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
/// Converts package errors into strings that can travel over op_result.
fn auto_launch_error(error : @sys_auto_launch.AutoLaunchError) -> String {
  error.to_string()
}

///|
/// Builds one launcher from JavaScript payload data.
fn build_launcher(
  payload : AutoLaunchPayload,
) -> Result[@sys_auto_launch.AutoLaunch, String] {
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
  launcher.map_err(auto_launch_error)
}

///|
fn auto_launch_payload(
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> AutoLaunchPayload {
  AutoLaunchPayload::{
    name,
    path,
    launch_in_background,
    background_arg,
    extra_arguments,
    identifier,
  }
}

///|
/// Converts a launcher into the serializable descriptor used by JS.
fn launcher_reply(launcher : @sys_auto_launch.AutoLaunch) -> AutoLaunchReply {
  AutoLaunchReply::{
    name: launcher.name(),
    path: launcher.path(),
    identifier: launcher.identifier(),
  }
}

///|
fn auto_launch_support() -> SupportReply {
  SupportReply::{
    supported: @sys_auto_launch.is_supported(),
    platform: platform_label(@sys_auto_launch.current_platform()),
  }
}

///|
fn describe_auto_launch(
  payload : AutoLaunchPayload,
) -> Result[AutoLaunchReply, String] {
  build_launcher(payload).map(launcher_reply)
}

///|
fn is_auto_launch_enabled(
  payload : AutoLaunchPayload,
) -> Result[EnabledReply, String] {
  build_launcher(payload).bind(fn(launcher) {
    launcher
    .is_enabled()
    .map_err(auto_launch_error)
    .map(fn(enabled) { EnabledReply::{ enabled, } })
  })
}

///|
fn enable_auto_launch(payload : AutoLaunchPayload) -> Result[String, String] {
  build_launcher(payload).bind(fn(launcher) {
    launcher
    .enable()
    .map_err(auto_launch_error)
    .map(fn(_) { launcher.identifier() })
  })
}

///|
fn disable_auto_launch(payload : AutoLaunchPayload) -> Result[String, String] {
  build_launcher(payload).bind(fn(launcher) {
    launcher
    .disable()
    .map_err(auto_launch_error)
    .map(fn(_) { launcher.identifier() })
  })
}
