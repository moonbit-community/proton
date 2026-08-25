///|
/// Returns the per-user LaunchAgent plist path for `identifier`.
fn launch_agent_path(home_directory : String, identifier : String) -> String {
  join_unix_path(
    join_unix_path(home_directory, "Library"),
    "LaunchAgents/" + identifier + ".plist",
  )
}

///|
/// Returns the XDG autostart desktop-entry path for `identifier`.
fn linux_desktop_path(home_directory : String, identifier : String) -> String {
  join_unix_path(
    join_unix_path(join_unix_path(home_directory, ".config"), "autostart"),
    identifier + ".desktop",
  )
}

///|
/// Renders the command string stored in the Windows `Run` registry value.
fn render_command_line(
  config : AutoLaunchConfig,
  quote_argument : (String) -> String,
) -> String {
  let quoted : Array[String] = []
  for argument in build_program_arguments(config) {
    quoted.push(quote_argument(argument))
  }
  quoted.join(" ")
}

///|
/// Renders the command string stored in the Windows `Run` registry value.
fn windows_command(config : AutoLaunchConfig) -> String {
  render_command_line(config, windows_quote_argument)
}

///|
/// Renders a freedesktop.org desktop-entry file for Linux auto-start.
fn linux_desktop_contents(config : AutoLaunchConfig) -> String {
  let exec_line = render_command_line(config, desktop_quote_argument)
  (
    $|[Desktop Entry]
    $|Type=Application
    $|Version=1.0
    $|Name=\{config.name}
    $|Comment=Launch \{config.name} automatically at login
    $|Exec=\{exec_line}
    $|Terminal=false
    $|StartupNotify=false
    $|
  )
}

///|
/// Renders the `<string>` items for a LaunchAgent `ProgramArguments` array.
fn plist_program_arguments(arguments : Array[String]) -> String {
  let builder = StringBuilder()
  for argument in arguments {
    builder.write_string("    <string>")
    builder.write_string(xml_escape(argument))
    builder.write_string("</string>\n")
  }
  builder.to_string()
}

///|
/// Renders a macOS LaunchAgent plist.
fn mac_launch_agent_contents(config : AutoLaunchConfig) -> String {
  let arguments = build_program_arguments(config)
  let argument_items = plist_program_arguments(arguments)
  (
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    $|<plist version="1.0">
    $|<dict>
    $|  <key>Label</key>
    $|  <string>\{xml_escape(config.identifier)}</string>
    $|  <key>ProgramArguments</key>
    $|  <array>
    $|\{argument_items}  </array>
    $|  <key>RunAtLoad</key>
    $|  <true/>
    $|</dict>
    $|</plist>
    $|
  )
}

///|
/// Produces the file-backed entry for macOS or Linux.
fn file_entry_result(
  config : AutoLaunchConfig,
  platform : Platform,
  home_directory : String,
) -> Result[FileEntry, AutoLaunchError] {
  match platform {
    Platform::Macos =>
      Ok(FileEntry::{
        file_path: launch_agent_path(home_directory, config.identifier),
        contents: mac_launch_agent_contents(config),
      })
    Platform::Linux =>
      Ok(FileEntry::{
        file_path: linux_desktop_path(home_directory, config.identifier),
        contents: linux_desktop_contents(config),
      })
    _ => Err(AutoLaunchError::UnsupportedPlatform(platform))
  }
}

///|
/// Resolves the concrete file entry for a launcher.
fn resolve_file_entry(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
) -> Result[FileEntry, AutoLaunchError] {
  match get_home_directory() {
    Ok(home_directory) =>
      file_entry_result(launcher.config, platform, home_directory)
    Err(error) => Err(error)
  }
}

///|
/// Writes a resolved file-backed launcher entry.
fn write_resolved_file_entry(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  write_file : (String, String) -> Result[Unit, AutoLaunchError],
) -> Result[Unit, AutoLaunchError] {
  match resolve_file_entry(launcher, platform, get_home_directory) {
    Ok(entry) => write_file(entry.file_path, entry.contents)
    Err(error) => Err(error)
  }
}

///|
/// Removes a resolved file-backed launcher entry.
fn remove_resolved_file_entry(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  remove_file : (String) -> Result[Unit, AutoLaunchError],
) -> Result[Unit, AutoLaunchError] {
  match resolve_file_entry(launcher, platform, get_home_directory) {
    Ok(entry) => remove_file(entry.file_path)
    Err(error) => Err(error)
  }
}

///|
/// Checks whether a resolved file-backed launcher entry exists.
fn resolved_file_entry_exists(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  file_exists : (String) -> Result[Bool, AutoLaunchError],
) -> Result[Bool, AutoLaunchError] {
  match resolve_file_entry(launcher, platform, get_home_directory) {
    Ok(entry) => file_exists(entry.file_path)
    Err(error) => Err(error)
  }
}

///|
/// Enables auto-launch using injected side-effect functions.
fn enable_with(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  set_windows_entry : (String, String) -> Result[Unit, AutoLaunchError],
  write_file : (String, String) -> Result[Unit, AutoLaunchError],
) -> Result[Unit, AutoLaunchError] {
  match platform {
    Platform::Windows =>
      set_windows_entry(
        launcher.config.identifier,
        windows_command(launcher.config),
      )
    Platform::Macos | Platform::Linux =>
      write_resolved_file_entry(
        launcher, platform, get_home_directory, write_file,
      )
    Platform::Unsupported => Err(AutoLaunchError::UnsupportedPlatform(platform))
  }
}

///|
/// Disables auto-launch using injected side-effect functions.
fn disable_with(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  delete_windows_entry : (String) -> Result[Unit, AutoLaunchError],
  remove_file : (String) -> Result[Unit, AutoLaunchError],
) -> Result[Unit, AutoLaunchError] {
  match platform {
    Platform::Windows => delete_windows_entry(launcher.config.identifier)
    Platform::Macos | Platform::Linux =>
      remove_resolved_file_entry(
        launcher, platform, get_home_directory, remove_file,
      )
    Platform::Unsupported => Err(AutoLaunchError::UnsupportedPlatform(platform))
  }
}

///|
/// Checks whether auto-launch is enabled using injected lookup functions.
fn is_enabled_with(
  launcher : AutoLaunch,
  platform : Platform,
  get_home_directory : () -> Result[String, AutoLaunchError],
  windows_entry_exists : (String) -> Result[Bool, AutoLaunchError],
  file_exists : (String) -> Result[Bool, AutoLaunchError],
) -> Result[Bool, AutoLaunchError] {
  match platform {
    Platform::Windows => windows_entry_exists(launcher.config.identifier)
    Platform::Macos | Platform::Linux =>
      resolved_file_entry_exists(
        launcher, platform, get_home_directory, file_exists,
      )
    Platform::Unsupported => Err(AutoLaunchError::UnsupportedPlatform(platform))
  }
}
