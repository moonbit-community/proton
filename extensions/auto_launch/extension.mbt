///|
let extension_id = "justjavac/lepus-auto-launch"

///|
let extension_namespace = "autoLaunch"

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

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
struct AutoLaunchActivity {
  operation : String
  identifier : String?
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
/// Emits an auto-launch activity event for JavaScript listeners.
fn emit_activity(
  extension : @core.ExtensionContext,
  operation : String,
  identifier : String?,
) -> Unit {
  extension.emit("activity", AutoLaunchActivity::{ operation, identifier })
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
/// Converts a launcher into the serializable descriptor used by JS.
fn launcher_reply(launcher : @sys_auto_launch.AutoLaunch) -> AutoLaunchReply {
  AutoLaunchReply::{
    name: launcher.name(),
    path: launcher.path(),
    identifier: launcher.identifier(),
  }
}

///|
/// Builds the `autoLaunch` extension for direct installation.
/// Install it manually when trusted local content needs to manage a desktop
/// startup entry for the current application.
pub fn extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) {
    extension.op("support", fn(_payload : EmptyPayload) {
      SupportReply::{
        supported: @sys_auto_launch.is_supported(),
        platform: platform_label(@sys_auto_launch.current_platform()),
      }
    })

    extension.op_result("describe", fn(payload : AutoLaunchPayload) {
      build_launcher(payload).map(launcher_reply)
    })

    extension.op_result("isEnabled", fn(payload : AutoLaunchPayload) {
      build_launcher(payload).bind(fn(launcher) {
        launcher
        .is_enabled()
        .map_err(auto_launch_error)
        .map(fn(enabled) { EnabledReply::{ enabled, } })
      })
    })

    extension.op_result("enable", fn(payload : AutoLaunchPayload) {
      build_launcher(payload).bind(fn(launcher) {
        launcher
        .enable()
        .map_err(auto_launch_error)
        .map(fn(_) {
          emit_activity(extension, "enable", Some(launcher.identifier()))
          MutationReply::{ changed: true }
        })
      })
    })

    extension.op_result("disable", fn(payload : AutoLaunchPayload) {
      build_launcher(payload).bind(fn(launcher) {
        launcher
        .disable()
        .map_err(auto_launch_error)
        .map(fn(_) {
          emit_activity(extension, "disable", Some(launcher.identifier()))
          MutationReply::{ changed: true }
        })
      })
    })
  })
}

///|
/// Builds the declarative `autoLaunch` extension spec.
/// Register this when startup-entry management should be selected through app
/// composition or generated registry code.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
