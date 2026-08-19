///|
priv enum PackageHost {
  Macos
  Windows
  Linux
} derive(Eq)

///|
async fn current_package_host() -> PackageHost {
  if @path.sep == '\\' {
    Windows
  } else if path_exists("/System/Library/CoreServices/SystemVersion.plist") {
    Macos
  } else {
    Linux
  }
}

///|
fn host_name(host : PackageHost) -> String {
  match host {
    Macos => "macOS"
    Windows => "Windows"
    Linux => "Linux"
  }
}

///|
fn format_supported(host : PackageHost, format : PackageFormat) -> Bool {
  match (host, format) {
    (Macos, App | Zip | Dmg) => true
    (Windows, App | Zip | Nsis) => true
    (Linux, AppImage) => true
    _ => false
  }
}

///|
/// Packages an already-built executable using the current host's native tools.
pub async fn build(spec : PackageSpec) -> Array[String] {
  build_with(spec, PackageCustomization::new(), fn(_layout) { () })
}

///|
/// Packages an executable and allows framework-specific staging before the
/// package is signed and converted into its requested artifacts.
pub async fn build_with(
  spec : PackageSpec,
  customization : PackageCustomization,
  prepare : async (PackageLayout) -> Unit,
) -> Array[String] {
  let spec = validate_spec(spec)
  validate_customization(customization)
  let host = current_package_host()
  for format in spec.formats {
    guard format_supported(host, format) else {
      raise PackagePlanError::UnsupportedFormatForPlatform(
        format=format.to_string(),
        platform=host_name(host),
      )
    }
  }
  ensure_dir(spec.output)
  match host {
    Macos => package_macos(spec, customization, prepare)
    Windows => package_windows(spec, customization, prepare)
    Linux => package_linux(spec, customization, prepare)
  }
}

///|
fn validate_customization(
  customization : PackageCustomization,
) -> Unit raise PackagePlanError {
  for property in customization.macos_plist_strings {
    guard property.key.trim().length() > 0 else {
      raise InvalidPayload(detail="macOS plist property key must not be empty")
    }
  }
  for target in customization.macos_sign_targets {
    validate_relative_destination(target.path)
  }
  for target in customization.windows_sign_targets {
    validate_relative_destination(target)
  }
  for target in customization.windows_verify_targets {
    validate_relative_destination(target)
  }
  match customization.linux_resources_path {
    Some(path) => validate_relative_destination(path)
    None => ()
  }
}

///|
fn validate_spec(spec : PackageSpec) -> PackageSpec raise PackagePlanError {
  let product_name = validate_product_name(spec.product_name)
  let identifier = validate_identifier(spec.identifier)
  let version = spec.version.trim().to_owned()
  guard version != "" else {
    raise InvalidVersion(version=spec.version, reason="must not be empty")
  }
  guard spec.formats.length() > 0 else {
    raise UnsupportedFormat(format="no format selected")
  }
  for payload in spec.payloads {
    validate_relative_destination(payload.destination)
  }
  PackageSpec::{
    ..spec,
    product_name,
    identifier,
    version,
    sign: spec.sign || spec.notarize,
  }
}

///|
fn validate_product_name(value : String) -> String raise PackagePlanError {
  let value = value.trim().to_owned()
  guard value != "" else {
    raise InvalidProductName(reason="value is required")
  }
  for char in value {
    let code = char.to_int()
    if code < 32 || code == 127 {
      raise InvalidProductName(reason="contains an ASCII control character")
    }
    if char == '/' || char == '\\' || char == ':' {
      raise InvalidProductName(
        reason="contains a path-unsafe character: " + char.to_string(),
      )
    }
  }
  value
}

///|
fn validate_identifier(value : String) -> String raise PackagePlanError {
  let value = value.trim().to_owned()
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 2 else {
    raise InvalidIdentifier(
      identifier=value,
      reason="expected a reverse-DNS bundle identifier",
    )
  }
  for component in components {
    guard component.length() > 0 else {
      raise InvalidIdentifier(
        identifier=value,
        reason="contains an empty component",
      )
    }
    let mut at_start = true
    for char in component {
      if at_start {
        guard char.is_ascii_alphabetic() || char.is_ascii_digit() else {
          raise InvalidIdentifier(
            identifier=value,
            reason="a component must start with an ASCII letter or digit",
          )
        }
        at_start = false
      }
      guard char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-' else {
        raise InvalidIdentifier(
          identifier=value,
          reason="contains an unsupported character",
        )
      }
    }
  }
  value
}

///|
fn validate_relative_destination(value : String) -> Unit raise PackagePlanError {
  let normalized = value.replace_all(old="\\", new="/")
  let path : @path.Path = normalized
  guard normalized != "" && !path.is_absolute() else {
    raise InvalidPayload(detail="destination must be a non-empty relative path")
  }
  for component in normalized.split("/") {
    guard component != ".." else {
      raise InvalidPayload(
        detail="destination must stay inside its package area",
      )
    }
  }
}

///|
fn executable_name(product_name : String) -> String {
  let mut output = ""
  let mut previous_dash = false
  for char in product_name.trim().to_owned().to_lower() {
    if char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '-' ||
      char == '_' {
      output = output + char.to_string()
      previous_dash = false
    } else if !previous_dash && output != "" {
      output = output + "-"
      previous_dash = true
    }
  }
  while output.has_suffix("-") {
    output = output
      .unsafe_substring(start=0, end=output.length() - 1)
      .to_string()
  }
  if output == "" {
    "app"
  } else {
    output
  }
}

///|
fn first_icon(spec : PackageSpec, suffix : String) -> String? {
  for icon in spec.icons {
    if icon.to_lower().has_suffix(suffix) {
      return Some(icon)
    }
  }
  None
}

///|
async fn path_exists(path : String) -> Bool {
  @async_fs.exists(path)
}

///|
async fn path_is_file(path : String) -> Bool {
  path_exists(path) && @async_fs.kind(path) is Regular
}

///|
async fn path_is_dir(path : String) -> Bool {
  path_exists(path) && @async_fs.kind(path) is Directory
}

///|
fn host_path(path : String) -> @path.Path {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
fn path_join(base : String, child : String) -> String {
  host_path(base).join(host_path(child)).to_string()
}

///|
fn path_parent(path : String) -> String {
  host_path(path).dirname().to_string()
}

///|
fn resolve_path(base : String, path : String) -> String {
  let candidate = host_path(path)
  if candidate.is_absolute() {
    candidate.resolve().to_string()
  } else {
    host_path(base).join(candidate).resolve().to_string()
  }
}

///|
async fn ensure_dir(path : String) -> Unit {
  guard !path_exists(path) else { return }
  let parent = path_parent(path)
  if parent != path && !path_exists(parent) {
    ensure_dir(parent)
  }
  @async_fs.mkdir(path) catch {
    error => {
      guard !path_exists(path) else { return }
      raise PackageFileSystemError::CreateDirectory(
        path~,
        detail=@debug.render(Repr(error)),
      )
    }
  }
}

///|
async fn remove_tree(path : String) -> Unit {
  guard path_exists(path) else { return }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      error =>
        raise PackageFileSystemError::Remove(
          path~,
          detail=@debug.render(Repr(error)),
        )
    }
  } else {
    @async_fs.rmdir(path, recursive=true) catch {
      error =>
        raise PackageFileSystemError::Remove(
          path~,
          detail=@debug.render(Repr(error)),
        )
    }
  }
}

///|
async fn copy_file(source : String, destination : String) -> Unit {
  guard path_is_file(source) else {
    raise PackagePlanError::MissingInput(path=source)
  }
  ensure_dir(path_parent(destination))
  if current_package_host() == Macos {
    let code = @process.run("ditto", [source, destination]) catch {
      error =>
        raise PackageFileSystemError::Copy(
          source~,
          destination~,
          detail=@debug.render(Repr(error)),
        )
    }
    guard code == 0 else {
      raise PackageToolError::Exit(tool="ditto", code~, detail=source)
    }
    return
  }
  let data = @async_fs.read_file(source) catch {
    error =>
      raise PackageFileSystemError::Read(
        path=source,
        detail=@debug.render(Repr(error)),
      )
  }
  @async_fs.write_file(destination, data, create_mode=CreateOrTruncate) catch {
    error =>
      raise PackageFileSystemError::Write(
        path=destination,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
async fn copy_tree(source : String, destination : String) -> Unit {
  if path_is_file(source) {
    return copy_file(source, destination)
  }
  guard path_is_dir(source) else {
    raise PackageFileSystemError::InvalidSource(path=source)
  }
  ensure_dir(path_parent(destination))
  let (tool, args) = match current_package_host() {
    Windows =>
      (
        "robocopy",
        [
          source, destination, "/E", "/COPY:DAT", "/DCOPY:DAT", "/NFL", "/NDL", "/NJH",
          "/NJS", "/NP", "/R:2", "/W:1",
        ],
      )
    Macos => ("ditto", [source, destination])
    Linux => ("cp", ["-R", source, destination])
  }
  let (code, _) = @process.collect_output_merged(tool, args) catch {
    error =>
      raise PackageFileSystemError::Copy(
        source~,
        destination~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 || (tool == "robocopy" && code < 8) else {
    raise PackageToolError::Exit(tool~, code~, detail=source)
  }
}

///|
async fn copy_payloads(
  spec : PackageSpec,
  resources : String,
  libraries : String,
  executables : String,
) -> Unit {
  for payload in spec.payloads {
    let root = match payload.location {
      Resources => resources
      Libraries => libraries
      Executables => executables
    }
    copy_tree(payload.source, path_join(root, payload.destination))
  }
}

///|
async fn write_text(path : String, text : String) -> Unit {
  ensure_dir(path_parent(path))
  @async_fs.write_file(path, text, create_mode=CreateOrTruncate) catch {
    error =>
      raise PackageFileSystemError::Write(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
async fn promote(source : String, destination : String) -> Unit {
  let backup = destination + ".backup"
  if path_exists(backup) {
    if path_exists(destination) {
      remove_tree(backup)
    } else {
      rename_package_path(backup, destination)
    }
  }
  let had_destination = path_exists(destination)
  if had_destination {
    rename_package_path(destination, backup)
  }
  rename_package_path(source, destination) catch {
    error => {
      if had_destination && path_exists(backup) {
        rename_package_path(backup, destination) catch {
          rollback_error =>
            raise PackageFileSystemError::Copy(
              source~,
              destination~,
              detail=@debug.render(Repr(error)) +
                "; restore failed: " +
                @debug.render(Repr(rollback_error)),
            )
        }
      }
      raise error
    }
  }
  if had_destination {
    remove_tree(backup) catch {
      _ => ()
    }
  }
}

///|
async fn rename_package_path(source : String, destination : String) -> Unit {
  @async_fs.rename(source, destination) catch {
    error =>
      raise PackageFileSystemError::Copy(
        source~,
        destination~,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
fn xml_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}
