///|
let default_package = "app"

///|
let default_config_file = "moon.proton"

///|
pub(all) enum PackageError {
  UsageError(String, Bool)
  CommandError(String)
} derive(Debug)

///|
struct RawPackageOptions {
  app_package : String
  config_path : String?
  targets : Array[String]
  output : String?
  build : Bool
  dry_run : Bool
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
struct PackagePlan {
  root : String
  workspace_root : String
  build_target_dir : String
  app_package : String
  config_path : String
  product_name : String
  identifier : String
  version : String
  macos_version : String
  bundle_version : String
  targets : Array[String]
  output : String
  build : Bool
  base_dir : String
  frontend_dist : String?
  entry_path : String?
  resources : Array[String]
  icons : Array[String]
  macos_icon : String?
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
struct MacosCodeSignTarget {
  path : String
  runtime_options : Bool
  deep : Bool
} derive(Debug, Eq)

///|
pub async fn run(
  cwd : String,
  args : Array[String],
) -> Result[Unit, PackageError] {
  if args.contains("-h") || args.contains("--help") {
    print_package_usage()
    return Ok(())
  }
  let raw = match parse_package_args(args) {
    Ok(raw) => raw
    Err(error) => return Err(error)
  }
  let cwd = @path.Path(cwd).resolve().to_string()
  let root = find_project_root_from(cwd)
  let config_path = match resolve_package_config_path(cwd, root, raw) {
    Some(path) => path
    None =>
      return Err(CommandError("proton package config not found: moon.proton"))
  }
  let project = match
    @proton_config.load_project_config_from_file(config_path) {
    Ok(project) => project
    Err(message) =>
      return Err(
        CommandError("failed to load `" + config_path + "`: " + message),
      )
  }
  let plan = match build_package_plan(raw, config_path, project) {
    Ok(plan) => plan
    Err(error) => return Err(error)
  }
  print_package_plan(plan, raw.dry_run)
  if raw.dry_run {
    return Ok(())
  }
  execute_package_plan(plan)
}

///|
fn print_package_usage() -> Unit {
  println("Usage:")
  println("  proton_cli [-C DIR] package [PACKAGE] [OPTIONS]")
  println("")
  println("Options:")
  println(
    "  --config <path>          Proton project config (default: package/cwd/root moon.proton)",
  )
  println("  --target <app|zip>       Override bundle.targets; may be repeated")
  println("  --output <dir>           Override bundle.output")
  println("  --no-build               Reuse an existing release build")
  println("  --dry-run                Print the resolved package plan")
  println("  --sign                   Sign the packaged application")
  println(
    "  --notarize               Sign, notarize, and staple a macOS application",
  )
}

///|
fn parse_package_args(
  args : Array[String],
) -> Result[RawPackageOptions, PackageError] {
  let targets : Array[String] = []
  let mut app_package : String? = None
  let mut config_path : String? = None
  let mut output : String? = None
  let mut build = true
  let mut dry_run = false
  let mut sign = false
  let mut notarize = false
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "--config" || arg == "--target" || arg == "--output" {
      let value = match read_option_value(args, index, arg) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if arg == "--config" {
        config_path = Some(value)
      } else if arg == "--target" {
        match validate_package_target(value) {
          Ok(_) => targets.push(value)
          Err(error) => return Err(error)
        }
      } else {
        output = Some(value)
      }
      index = index + 2
    } else if arg == "--no-build" {
      build = false
      index = index + 1
    } else if arg == "--dry-run" {
      dry_run = true
      index = index + 1
    } else if arg == "--sign" {
      sign = true
      index = index + 1
    } else if arg == "--notarize" {
      sign = true
      notarize = true
      index = index + 1
    } else if arg.has_prefix("-") {
      return Err(UsageError("unknown package option: " + arg, false))
    } else {
      match app_package {
        None => {
          app_package = Some(arg)
          index = index + 1
        }
        Some(_) =>
          return Err(
            UsageError("package accepts at most one package argument", false),
          )
      }
    }
  }
  Ok(RawPackageOptions::{
    app_package: app_package.unwrap_or(default_package),
    config_path,
    targets,
    output,
    build,
    dry_run,
    sign,
    notarize,
  })
}

///|
fn validate_package_target(target : String) -> Result[Unit, PackageError] {
  if target == "app" || target == "zip" {
    Ok(())
  } else {
    Err(UsageError("unsupported package target: " + target, false))
  }
}

///|
fn read_option_value(
  args : Array[String],
  index : Int,
  flag : String,
) -> Result[String, PackageError] {
  if index + 1 >= args.length() || args[index + 1] == "" {
    Err(UsageError(flag + " requires a value", false))
  } else {
    Ok(args[index + 1])
  }
}

///|
fn build_package_plan(
  raw : RawPackageOptions,
  config_path : String,
  project : @proton_config.ProjectConfig,
) -> Result[PackagePlan, PackageError] {
  let bundle = match project.bundle() {
    Some(bundle) if bundle.active() => bundle
    Some(_) =>
      return Err(CommandError("bundle.active must be true for proton package"))
    None =>
      return Err(CommandError("bundle config is required for proton package"))
  }
  let metadata = project.metadata()
  let product_name = match validate_product_name(metadata.product_name) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let identifier = match metadata.identifier {
    Some(identifier) => identifier
    None =>
      return Err(CommandError("identifier is required for proton package"))
  }
  let version = match metadata.version {
    Some(version) => version
    None =>
      return Err(
        CommandError("moon.mod version is required for proton package"),
      )
  }
  let identifier = match validate_bundle_identifier(identifier) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let version = version.trim().to_owned()
  guard version != "" else {
    return Err(CommandError("moon.mod version is required for proton package"))
  }
  let (macos_version, bundle_version) = if is_macos_host() {
    match validate_macos_version(version) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else {
    (version, version)
  }
  let targets = if raw.targets.length() > 0 {
    copy_strings(raw.targets)
  } else if bundle.targets.length() > 0 {
    copy_strings(bundle.targets)
  } else {
    ["app", "zip"]
  }
  let base_dir = resolve_path(project.base_dir(), ".")
  let output = match raw.output {
    Some(output) => resolve_path(base_dir, output)
    None => resolve_path(base_dir, bundle.output())
  }
  let frontend_dist = match project.frontend() {
    Some(frontend) => frontend.dist()
    None => None
  }
  let entry_path = match project.entry() {
    File(path) | Asset(path) => Some(path)
    Html(_) | Url(_) => None
  }
  let workspace_root = find_workspace_root_from(base_dir)
  Ok(PackagePlan::{
    root: find_project_root_from(base_dir),
    workspace_root,
    build_target_dir: package_build_target_dir(workspace_root, identifier),
    app_package: raw.app_package,
    config_path,
    product_name,
    identifier,
    version,
    macos_version,
    bundle_version,
    targets,
    output,
    build: raw.build,
    base_dir,
    frontend_dist,
    entry_path,
    resources: copy_strings(bundle.resources),
    icons: copy_strings(bundle.icon),
    macos_icon: first_macos_icon(bundle.icon),
    sign: raw.sign,
    notarize: raw.notarize,
  })
}

///|
fn validate_product_name(value : String) -> Result[String, PackageError] {
  let value = value.trim().to_owned()
  guard value != "" else {
    return Err(CommandError("product_name is required for proton package"))
  }
  for char in value {
    let code = char.to_int()
    if code < 32 || code == 127 {
      return Err(
        CommandError("product_name contains an ASCII control character"),
      )
    }
    if char == '/' || char == '\\' || char == ':' {
      return Err(
        CommandError(
          "product_name contains a path-unsafe character: " + char.to_string(),
        ),
      )
    }
  }
  Ok(value)
}

///|
fn validate_bundle_identifier(value : String) -> Result[String, PackageError] {
  let value = value.trim().to_owned()
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 2 else {
    return Err(
      CommandError(
        "identifier must be a reverse-DNS bundle identifier: " + value,
      ),
    )
  }
  for component in components {
    guard component.length() > 0 else {
      return Err(
        CommandError("identifier contains an empty component: " + value),
      )
    }
    let mut at_start = true
    for char in component {
      if at_start {
        guard char.is_ascii_alphabetic() || char.is_ascii_digit() else {
          return Err(
            CommandError(
              "identifier component must start with an ASCII letter or digit: " +
              value,
            ),
          )
        }
        at_start = false
      }
      guard char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-' else {
        return Err(
          CommandError("identifier contains an unsupported character: " + value),
        )
      }
    }
  }
  Ok(value)
}

///|
fn validate_macos_version(
  value : String,
) -> Result[(String, String), PackageError] {
  let value = value.trim().to_owned()
  let core = match value.split_once("-") {
    Some((core, _)) => core.to_owned()
    None => value
  }
  let core = match core.split_once("+") {
    Some((core, _)) => core.to_owned()
    None => core
  }
  let components : Array[StringView] = core.split(".").collect()
  guard components.length() >= 1 && components.length() <= 3 else {
    return Err(
      CommandError(
        "macOS version must contain one to three numeric components: " + core,
      ),
    )
  }
  let normalized : Array[String] = []
  for component in components {
    guard component.length() > 0 else {
      return Err(
        CommandError("macOS version contains an empty component: " + core),
      )
    }
    for char in component {
      guard char.is_ascii_digit() else {
        return Err(
          CommandError("macOS version components must be numeric: " + core),
        )
      }
    }
    normalized.push(component.to_owned())
  }
  while normalized.length() < 3 {
    normalized.push("0")
  }
  let short_version = normalized.join(".")
  let bundle_version = match @sys.get_env_var("PROTON_MACOS_BUILD_NUMBER") {
    Some(build) if build.trim().to_owned() != "" =>
      match validate_bundle_version(build.trim().to_owned()) {
        Ok(build) => build
        Err(error) => return Err(error)
      }
    _ => short_version
  }
  Ok((short_version, bundle_version))
}

///|
fn validate_bundle_version(value : String) -> Result[String, PackageError] {
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 1 && components.length() <= 3 else {
    return Err(
      CommandError(
        "PROTON_MACOS_BUILD_NUMBER must contain one to three numeric components",
      ),
    )
  }
  for component in components {
    guard component.length() > 0 else {
      return Err(
        CommandError("PROTON_MACOS_BUILD_NUMBER contains an empty component"),
      )
    }
    for char in component {
      guard char.is_ascii_digit() else {
        return Err(
          CommandError("PROTON_MACOS_BUILD_NUMBER components must be numeric"),
        )
      }
    }
  }
  Ok(value)
}

///|
fn first_macos_icon(icons : Array[String]) -> String? {
  for icon in icons {
    if icon.to_lower().has_suffix(".icns") {
      return Some(icon)
    }
  }
  None
}

///|
fn print_package_plan(plan : PackagePlan, dry_run : Bool) -> Unit {
  if dry_run {
    println("Proton package plan (dry run):")
  } else {
    println("Proton package plan:")
  }
  println("  package: " + plan.app_package)
  println("  config: " + plan.config_path)
  println("  product: " + plan.product_name)
  println("  identifier: " + plan.identifier)
  println("  version: " + plan.version)
  println("  targets: " + plan.targets.join(", "))
  println("  output: " + plan.output)
  println("  build target: " + plan.build_target_dir)
  let build = if plan.build { "yes" } else { "no" }
  println("  build: " + build)
  println("  sign: " + bool_text(plan.sign))
  println("  notarize: " + bool_text(plan.notarize))
}

///|
fn bool_text(value : Bool) -> String {
  if value {
    "yes"
  } else {
    "no"
  }
}

///|
async fn execute_package_plan(plan : PackagePlan) -> Result[Unit, PackageError] {
  if plan.build {
    match run_release_build(plan) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let executable = match find_release_executable(plan) {
    Some(path) => path
    None =>
      return Err(
        CommandError(
          "package release executable not found under " +
          plan.build_target_dir +
          "; run proton package without --no-build first",
        ),
      )
  }
  let runtime = match read_active_runtime(plan.workspace_root) {
    Ok(runtime) => runtime
    Err(error) => return Err(error)
  }
  if @path.sep == '\\' {
    stage_windows_portable(plan, executable, runtime)
  } else if is_macos_host() {
    stage_macos_app(plan, executable, runtime)
  } else {
    Err(CommandError("proton package currently supports macOS and Windows"))
  }
}

///|
fn is_macos_host() -> Bool {
  @mbfs.path_exists("/System/Library/CoreServices/SystemVersion.plist")
}

///|
async fn run_release_build(plan : PackagePlan) -> Result[Unit, PackageError] {
  let args = [
    plan.app_package,
    "--config",
    plan.config_path,
    "--",
    "--release",
    "--target-dir",
    plan.build_target_dir,
  ]
  let old_rpath = @sys.get_env_var("PROTON_PACKAGE_RPATH")
  if @path.sep != '\\' {
    @sys.set_env_var(
      "PROTON_PACKAGE_RPATH", "@executable_path/../Resources/proton/lib",
    )
  }
  defer restore_package_env("PROTON_PACKAGE_RPATH", old_rpath)
  match @build.run(plan.root, args) {
    Ok(_) => Ok(())
    Err(error) =>
      match error {
        UsageError(message, _) | CommandError(message) =>
          Err(CommandError(message))
      }
  }
}

///|
fn restore_package_env(name : String, value : String?) -> Unit {
  match value {
    Some(value) => @sys.set_env_var(name, value)
    None => @sys.unset_env_var(name)
  }
}

///|
fn find_release_executable(plan : PackagePlan) -> String? {
  let root = resolve_path(plan.build_target_dir, "native/release/build")
  let package_name = path_basename(plan.app_package)
  find_named_file(root, package_name + ".exe")
}

///|
fn find_named_file(root : String, name : String) -> String? {
  guard @mbfs.path_exists(root) else { return None }
  if path_is_file(root) {
    return if path_basename(root) == name { Some(root) } else { None }
  }
  let entries = @mbfs.read_dir(root) catch { _ => return None }
  for entry in entries {
    match find_named_file(resolve_path(root, entry), name) {
      Some(path) => return Some(path)
      None => ()
    }
  }
  None
}

///|
async fn read_active_runtime(root : String) -> Result[String, PackageError] {
  match @sys.get_env_var("PROTON_NATIVE_DIST") {
    Some(value) if value.trim().to_owned() != "" =>
      return require_runtime(resolve_path(root, value.trim().to_owned()))
    _ => ()
  }
  let manifest_path = resolve_path(root, ".proton/runtime.json")
  let text = @mbfs.read_file_to_string(manifest_path, encoding="utf8") catch {
    _ =>
      return Err(
        CommandError("active Proton runtime is missing: " + manifest_path),
      )
  }
  let json = @json.parse(text) catch {
    error =>
      return Err(
        CommandError(
          "failed to parse active Proton runtime manifest: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  match json {
    Object(fields) => {
      let platform = match fields.get("platform") {
        Some(String(platform)) => platform
        _ =>
          return Err(
            CommandError(
              "active Proton runtime manifest has no string platform: " +
              manifest_path,
            ),
          )
      }
      let expected_platform = @cef.current_platform_id()
      guard platform == expected_platform else {
        return Err(
          CommandError(
            "active Proton runtime platform mismatch: expected " +
            expected_platform +
            ", got " +
            platform,
          ),
        )
      }
      match fields.get("dist") {
        Some(String(dist)) => require_runtime(resolve_path(root, dist))
        _ =>
          Err(
            CommandError(
              "active Proton runtime manifest has no string dist: " +
              manifest_path,
            ),
          )
      }
    }
    _ =>
      Err(
        CommandError(
          "active Proton runtime manifest root must be an object: " +
          manifest_path,
        ),
      )
  }
}

///|
fn package_build_target_dir(
  workspace_root : String,
  identifier : String,
) -> String {
  resolve_path(
    workspace_root,
    "target/proton-package-build/" + package_executable_name(identifier),
  )
}

///|
fn require_runtime(path : String) -> Result[String, PackageError] {
  if path_is_dir(path) {
    Ok(path)
  } else {
    Err(CommandError("active Proton runtime directory is missing: " + path))
  }
}

///|
async fn stage_macos_app(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Result[Unit, PackageError] {
  let staging = macos_staging_app_path(plan)
  let result = stage_macos_app_impl(plan, executable, runtime)
  match result {
    Ok(_) => Ok(())
    Err(error) => {
      ignore(remove_tree(staging))
      Err(error)
    }
  }
}

///|
async fn stage_macos_app_impl(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Result[Unit, PackageError] {
  let final_app = resolve_path(plan.output, plan.product_name + ".app")
  let executable_name = package_executable_name(plan.product_name)
  let app = macos_staging_app_path(plan)
  let contents = resolve_path(app, "Contents")
  let macos = resolve_path(contents, "MacOS")
  let resources = resolve_path(contents, "Resources")
  let frameworks = resolve_path(contents, "Frameworks")
  let helper_app = resolve_path(frameworks, plan.product_name + " Helper.app")
  let helper_macos = resolve_path(helper_app, "Contents/MacOS")
  match remove_tree(app) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for dir in [macos, resources, frameworks, helper_macos] {
    match ensure_dir(dir) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match copy_file(executable, resolve_path(macos, executable_name)) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match copy_tree(runtime, resolve_path(resources, "proton")) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match copy_file(plan.config_path, resolve_path(resources, "moon.proton")) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match stage_project_inputs(plan, resources) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match stage_macos_icon(plan, resources) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let helper_source = resolve_path(runtime, "bin/cef_process")
  guard @mbfs.path_exists(helper_source) else {
    return Err(
      CommandError("active Proton runtime helper is missing: " + helper_source),
    )
  }
  match copy_file(helper_source, resolve_path(helper_macos, "cef_process")) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    write_text(
      resolve_path(contents, "Info.plist"),
      macos_info_plist(plan, executable_name),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    write_text(
      resolve_path(helper_app, "Contents/Info.plist"),
      helper_info_plist(plan),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match write_package_manifest(plan, resources, "macos-app") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    add_macos_rpath(
      resolve_path(helper_macos, "cef_process"),
      "@loader_path/../../../../Resources/proton/lib",
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if plan.sign {
    match sign_macos_app(plan, app, executable_name) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if plan.notarize {
    match notarize_macos_app(plan, app) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match promote_staged_app(app, final_app) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  println("Packaged macOS app: " + final_app)
  if plan.targets.contains("zip") {
    match create_zip(plan, final_app) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn macos_staging_app_path(plan : PackagePlan) -> String {
  resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging.app",
  )
}

///|
async fn promote_staged_app(
  staging : String,
  destination : String,
) -> Result[Unit, PackageError] {
  let backup = destination + ".backup"
  if @mbfs.path_exists(backup) {
    if @mbfs.path_exists(destination) {
      match remove_tree(backup) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    } else {
      @async_fs.rename(backup, destination) catch {
        error =>
          return Err(
            CommandError(
              "failed to restore interrupted macOS app promotion from " +
              backup +
              ": " +
              @debug.render(@debug.to_repr(error)),
            ),
          )
      }
    }
  }
  let had_destination = @mbfs.path_exists(destination)
  if had_destination {
    @async_fs.rename(destination, backup) catch {
      error =>
        return Err(
          CommandError(
            "failed to preserve existing macOS app: " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  }
  @async_fs.rename(staging, destination) catch {
    error => {
      if had_destination {
        @async_fs.rename(backup, destination) catch {
          rollback_error =>
            return Err(
              CommandError(
                "failed to promote staged macOS app: " +
                @debug.render(@debug.to_repr(error)) +
                "; rollback also failed and the previous app remains at " +
                backup +
                ": " +
                @debug.render(@debug.to_repr(rollback_error)),
              ),
            )
        }
      }
      return Err(
        CommandError(
          "failed to promote staged macOS app: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
    }
  }
  match remove_tree(backup) {
    Err(error) =>
      Err(
        CommandError(
          "macOS app was promoted but its backup could not be removed: " +
          backup +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
    Ok(_) => Ok(())
  }
}

///|
async fn stage_project_inputs(
  plan : PackagePlan,
  destination : String,
) -> Result[Unit, PackageError] {
  let inputs : Array[String] = []
  match plan.frontend_dist {
    Some(path) => inputs.push(path)
    None => ()
  }
  match plan.entry_path {
    Some(path) => inputs.push(path)
    None => ()
  }
  for path in plan.resources {
    inputs.push(path)
  }
  let copied : Map[String, Bool] = Map([])
  for input in inputs {
    guard copied.get(input) is None else { continue }
    copied[input] = true
    let source = match glob_tree_root(input) {
      Some(root) => root
      None if input.contains("*") =>
        return Err(CommandError("unsupported bundle.resources glob: " + input))
      None => input
    }
    guard @mbfs.path_exists(source) else {
      return Err(CommandError("package input is missing: " + input))
    }
    let relative = match relative_to_base(plan.base_dir, source) {
      Some(relative) => relative
      None =>
        return Err(
          CommandError(
            "package input must be inside the config directory: " + input,
          ),
        )
    }
    match copy_tree(source, resolve_path(destination, relative)) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn glob_tree_root(path : String) -> String? {
  if normalize_slashes(path).has_suffix("/**") {
    Some(path.unsafe_substring(start=0, end=path.length() - 3).to_string())
  } else {
    None
  }
}

///|
async fn stage_macos_icon(
  plan : PackagePlan,
  resources : String,
) -> Result[Unit, PackageError] {
  match plan.macos_icon {
    None => Ok(())
    Some(icon) => {
      guard @mbfs.path_exists(icon) else {
        return Err(CommandError("macOS icon is missing: " + icon))
      }
      copy_file(icon, resolve_path(resources, "AppIcon.icns"))
    }
  }
}

///|
fn relative_to_base(base : String, path : String) -> String? {
  let base = normalize_slashes(resolve_path(base, "."))
  let path = normalize_slashes(resolve_path(base, path))
  let prefix = if base.has_suffix("/") { base } else { base + "/" }
  if path == base {
    Some(".")
  } else if path.has_prefix(prefix) {
    Some(
      path
      .unsafe_substring(start=prefix.length(), end=path.length())
      .to_string(),
    )
  } else {
    None
  }
}

///|
fn normalize_slashes(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn path_basename(path : String) -> String {
  let normalized = normalize_slashes(path)
  match normalized.rev_find("/") {
    Some(index) =>
      normalized
      .unsafe_substring(start=index + 1, end=normalized.length())
      .to_string()
    None => normalized
  }
}

///|
fn package_executable_name(product_name : String) -> String {
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
    "proton-app"
  } else {
    output
  }
}

///|
async fn ensure_dir(path : String) -> Result[Unit, PackageError] {
  guard !@mbfs.path_exists(path) else { return Ok(()) }
  let parent = path_parent(path)
  if parent != path && !@mbfs.path_exists(parent) {
    match ensure_dir(parent) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  @async_fs.mkdir(path) catch {
    error => {
      if @mbfs.path_exists(path) {
        return Ok(())
      }
      return Err(
        CommandError(
          "failed to create directory " +
          path +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
    }
  }
  Ok(())
}

///|
async fn remove_tree(path : String) -> Result[Unit, PackageError] {
  guard @mbfs.path_exists(path) else { return Ok(()) }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      error =>
        return Err(
          CommandError(
            "failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  } else {
    @async_fs.rmdir(path, recursive=true) catch {
      error =>
        return Err(
          CommandError(
            "failed to remove directory " +
            path +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  }
  Ok(())
}

///|
async fn copy_file(
  source : String,
  destination : String,
) -> Result[Unit, PackageError] {
  match ensure_dir(path_parent(destination)) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if is_macos_host() {
    let code = @process.run("ditto", [source, destination]) catch {
      error =>
        return Err(
          CommandError(
            "failed to copy " +
            source +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    return if code == 0 {
      Ok(())
    } else {
      Err(CommandError("ditto exited with code " + code.to_string()))
    }
  }
  let data = @async_fs.read_file(source) catch {
    error =>
      return Err(
        CommandError(
          "failed to read " +
          source +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  @async_fs.write_file(destination, data, create_mode=CreateOrTruncate) catch {
    error =>
      return Err(
        CommandError(
          "failed to write " +
          destination +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  Ok(())
}

///|
async fn copy_tree(
  source : String,
  destination : String,
) -> Result[Unit, PackageError] {
  if path_is_file(source) {
    return copy_file(source, destination)
  }
  guard path_is_dir(source) else {
    return Err(
      CommandError("package input is not a file or directory: " + source),
    )
  }
  match ensure_dir(path_parent(destination)) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let code = if @path.sep == '\\' {
    let (code, _) = @process.collect_output_merged("robocopy", [
      source, destination, "/E", "/COPY:DAT", "/DCOPY:DAT", "/NFL", "/NDL", "/NJH",
      "/NJS", "/NP", "/R:2", "/W:1",
    ]) catch {
      error =>
        return Err(
          CommandError(
            "failed to copy directory " +
            source +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    code
  } else if is_macos_host() {
    let (code, _) = @process.collect_output_merged("ditto", [
      source, destination,
    ]) catch {
      error =>
        return Err(
          CommandError(
            "failed to copy directory " +
            source +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    code
  } else {
    let (code, _) = @process.collect_output_merged("cp", [
      "-R", source, destination,
    ]) catch {
      error =>
        return Err(
          CommandError(
            "failed to copy directory " +
            source +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    code
  }
  if code == 0 || (@path.sep == '\\' && code < 8) {
    Ok(())
  } else {
    Err(
      CommandError(
        "directory copy exited with code " + code.to_string() + ": " + source,
      ),
    )
  }
}

///|
fn write_text(path : String, text : String) -> Result[Unit, PackageError] {
  @mbfs.write_string_to_file(path, text, encoding="utf8") catch {
    error =>
      return Err(
        CommandError(
          "failed to write " +
          path +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  Ok(())
}

///|
fn xml_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn macos_info_plist(plan : PackagePlan, executable : String) -> String {
  let template =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0"><dict>
    #|<key>CFBundleDisplayName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundleExecutable</key><string>{{EXECUTABLE}}</string>
    #|<key>CFBundleIdentifier</key><string>{{IDENTIFIER}}</string>
    #|{{ICON}}
    #|<key>CFBundleName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{MACOS_VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{BUNDLE_VERSION}}</string>
    #|<key>LSMinimumSystemVersion</key><string>12.0</string>
    #|<key>NSHighResolutionCapable</key><true/>
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{PRODUCT}}", new=xml_escape(plan.product_name))
  .replace_all(old="{{EXECUTABLE}}", new=xml_escape(executable))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(plan.identifier))
  .replace_all(old="{{VERSION}}", new=xml_escape(plan.version))
  .replace_all(old="{{MACOS_VERSION}}", new=xml_escape(plan.macos_version))
  .replace_all(old="{{BUNDLE_VERSION}}", new=xml_escape(plan.bundle_version))
  .replace_all(old="{{ICON}}", new=macos_icon_plist_entry(plan.macos_icon))
}

///|
fn macos_icon_plist_entry(icon : String?) -> String {
  match icon {
    Some(_) => "<key>CFBundleIconFile</key><string>AppIcon</string>"
    None => ""
  }
}

///|
fn helper_info_plist(plan : PackagePlan) -> String {
  let template =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0"><dict>
    #|<key>CFBundleExecutable</key><string>cef_process</string>
    #|<key>CFBundleIdentifier</key><string>{{IDENTIFIER}}.helper</string>
    #|<key>CFBundleName</key><string>{{PRODUCT}} Helper</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{MACOS_VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{BUNDLE_VERSION}}</string>
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{PRODUCT}}", new=xml_escape(plan.product_name))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(plan.identifier))
  .replace_all(old="{{VERSION}}", new=xml_escape(plan.version))
  .replace_all(old="{{MACOS_VERSION}}", new=xml_escape(plan.macos_version))
  .replace_all(old="{{BUNDLE_VERSION}}", new=xml_escape(plan.bundle_version))
}

///|
fn write_package_manifest(
  plan : PackagePlan,
  destination : String,
  kind : String,
) -> Result[Unit, PackageError] {
  let json = Json::object({
    "schema_version": Json::number(1),
    "kind": Json::string(kind),
    "product_name": Json::string(plan.product_name),
    "identifier": Json::string(plan.identifier),
    "version": Json::string(plan.version),
    "bundle_version": Json::string(plan.bundle_version),
    "targets": Json::array(
      plan.targets.map(fn(target) { Json::string(target) }),
    ),
  }).stringify()
  write_text(resolve_path(destination, "proton-package.json"), json + "\n")
}

///|
async fn add_macos_rpath(
  binary : String,
  rpath : String,
) -> Result[Unit, PackageError] {
  let code = @process.run("install_name_tool", ["-add_rpath", rpath, binary]) catch {
    error =>
      return Err(
        CommandError(
          "failed to run install_name_tool: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(CommandError("install_name_tool exited with code " + code.to_string()))
  }
}

///|
async fn sign_macos_app(
  plan : PackagePlan,
  app : String,
  executable_name : String,
) -> Result[Unit, PackageError] {
  let identity = match @sys.get_env_var("PROTON_MACOS_SIGNING_IDENTITY") {
    Some(identity) if identity.trim().to_owned() != "" =>
      identity.trim().to_owned()
    _ =>
      return Err(
        CommandError(
          "--sign requires PROTON_MACOS_SIGNING_IDENTITY with a Developer ID Application identity",
        ),
      )
  }
  let is_adhoc = match
    validate_macos_signing_identity(identity, notarize=plan.notarize) {
    Ok(is_adhoc) => is_adhoc
    Err(error) => return Err(error)
  }
  let contents = resolve_path(app, "Contents")
  let entitlements = match
    resolve_macos_entitlements(app, allow_untrusted_libraries=is_adhoc) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  let helper = resolve_path(
    contents,
    "Frameworks/" + plan.product_name + " Helper.app",
  )
  let main = resolve_path(contents, "MacOS/" + executable_name)
  let cef_framework = resolve_path(
    contents, "Resources/proton/Frameworks/Chromium Embedded Framework.framework",
  )
  let libproton = resolve_path(contents, "Resources/proton/lib/libproton.dylib")
  let runtime_bin = resolve_path(contents, "Resources/proton/bin")
  let targets = [
    MacosCodeSignTarget::{
      path: cef_framework,
      runtime_options: false,
      deep: true,
    },
    MacosCodeSignTarget::{
      path: resolve_path(runtime_bin, "libEGL.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: resolve_path(runtime_bin, "libGLESv2.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: resolve_path(runtime_bin, "libvk_swiftshader.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: resolve_path(runtime_bin, "cef_process"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: libproton,
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{ path: helper, runtime_options: true, deep: false },
    MacosCodeSignTarget::{ path: main, runtime_options: true, deep: false },
    MacosCodeSignTarget::{ path: app, runtime_options: true, deep: true },
  ]
  match require_macos_codesign_targets(targets) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for target in targets {
    match
      codesign_target(
        identity,
        target.path,
        runtime_options=target.runtime_options,
        deep=target.deep,
        entitlements=Some(entitlements),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  for target in targets {
    match verify_macos_codesign_target(target.path, deep=target.deep) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if is_adhoc {
    Ok(())
  } else {
    verify_macos_developer_id(app)
  }
}

///|
fn require_macos_codesign_targets(
  targets : Array[MacosCodeSignTarget],
) -> Result[Unit, PackageError] {
  for target in targets {
    guard @mbfs.path_exists(target.path) else {
      return Err(
        CommandError("required macOS signing target is missing: " + target.path),
      )
    }
  }
  Ok(())
}

///|
fn validate_macos_signing_identity(
  identity : String,
  notarize~ : Bool,
) -> Result[Bool, PackageError] {
  if identity != "-" {
    return Ok(false)
  }
  if !macos_adhoc_signing_allowed() {
    return Err(
      CommandError(
        "ad-hoc signing is not a release path; set PROTON_MACOS_ALLOW_ADHOC=1 only for local diagnostics",
      ),
    )
  }
  if notarize {
    return Err(
      CommandError(
        "--notarize requires a Developer ID Application identity; ad-hoc signing is diagnostic only",
      ),
    )
  }
  Ok(true)
}

///|
fn macos_adhoc_signing_allowed() -> Bool {
  match @sys.get_env_var("PROTON_MACOS_ALLOW_ADHOC") {
    Some(value) =>
      match value.trim().to_owned().to_lower() {
        "1" | "true" | "yes" | "on" => true
        _ => false
      }
    None => false
  }
}

///|
async fn verify_macos_developer_id(app : String) -> Result[Unit, PackageError] {
  let (code, output) = @process.collect_output_merged("codesign", [
    "--display", "--verbose=4", app,
  ]) catch {
    error =>
      return Err(
        CommandError(
          "failed to inspect macOS signing authority: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  guard code == 0 else {
    return Err(CommandError("failed to inspect macOS signing authority"))
  }
  let text = output.text() catch {
    error =>
      return Err(
        CommandError(
          "failed to decode macOS signing authority: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if text.contains("Authority=Developer ID Application:") {
    Ok(())
  } else {
    Err(
      CommandError(
        "macOS release signing must use a Developer ID Application identity",
      ),
    )
  }
}

///|
async fn codesign_target(
  identity : String,
  target : String,
  runtime_options~ : Bool,
  deep~ : Bool,
  entitlements~ : String?,
) -> Result[Unit, PackageError] {
  let args = macos_codesign_args(
    identity,
    target,
    runtime_options~,
    deep~,
    entitlements~,
  )
  let code = @process.run("codesign", args) catch {
    error =>
      return Err(
        CommandError(
          "failed to sign " +
          target +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(
      CommandError(
        "codesign exited with code " + code.to_string() + ": " + target,
      ),
    )
  }
}

///|
async fn verify_macos_codesign_target(
  target : String,
  deep~ : Bool,
) -> Result[Unit, PackageError] {
  let args = macos_codesign_verify_args(target, deep~)
  let code = @process.run("codesign", args) catch {
    error =>
      return Err(
        CommandError(
          "failed to verify macOS signature for " +
          target +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(
      CommandError(
        "codesign verification exited with code " +
        code.to_string() +
        ": " +
        target,
      ),
    )
  }
}

///|
fn macos_codesign_verify_args(target : String, deep~ : Bool) -> Array[String] {
  let args : Array[String] = ["--verify"]
  if deep {
    args.push("--deep")
  }
  args.push("--strict")
  args.push("--verbose=2")
  args.push(target)
  args
}

///|
fn macos_codesign_args(
  identity : String,
  target : String,
  runtime_options~ : Bool,
  deep~ : Bool,
  entitlements~ : String?,
) -> Array[String] {
  let args : Array[String] = ["--force", "--timestamp", "--sign", identity]
  if deep {
    args.push("--deep")
  }
  if runtime_options {
    args.push("--options")
    args.push("runtime")
  }
  match entitlements {
    Some(path) if runtime_options => {
      args.push("--entitlements")
      args.push(path)
    }
    _ => ()
  }
  args.push(target)
  args
}

///|
fn resolve_macos_entitlements(
  app : String,
  allow_untrusted_libraries~ : Bool,
) -> Result[String, PackageError] {
  match @sys.get_env_var("PROTON_MACOS_ENTITLEMENTS") {
    Some(path) if path.trim().to_owned() != "" => {
      let path = @path.Path(path.trim().to_owned()).resolve().to_string()
      if path_is_file(path) {
        Ok(path)
      } else {
        Err(CommandError("macOS entitlements file is missing: " + path))
      }
    }
    _ => {
      let path = resolve_path(app, "Contents/Resources/proton.entitlements")
      match
        write_text(path, default_macos_entitlements(allow_untrusted_libraries~)) {
        Ok(_) => Ok(path)
        Err(error) => Err(error)
      }
    }
  }
}

///|
fn default_macos_entitlements(allow_untrusted_libraries~ : Bool) -> String {
  let library_validation = if allow_untrusted_libraries {
    "<key>com.apple.security.cs.disable-library-validation</key><true/>\n"
  } else {
    ""
  }
  (
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0"><dict>
    #|<key>com.apple.security.cs.allow-jit</key><true/>
    #|<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    #|{{LIBRARY_VALIDATION}}
    #|</dict></plist>
    #|
  ).replace_all(old="{{LIBRARY_VALIDATION}}", new=library_validation)
}

///|
async fn notarize_macos_app(
  plan : PackagePlan,
  app : String,
) -> Result[Unit, PackageError] {
  let profile = match @sys.get_env_var("PROTON_NOTARY_PROFILE") {
    Some(profile) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    _ => return Err(CommandError("--notarize requires PROTON_NOTARY_PROFILE"))
  }
  let archive = resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".notary.zip",
  )
  match remove_tree(archive) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let result = submit_macos_notarization(app, archive, profile)
  let cleanup = remove_tree(archive)
  finish_macos_notarization(result, cleanup, archive)
}

///|
fn finish_macos_notarization(
  result : Result[Unit, PackageError],
  cleanup : Result[Unit, PackageError],
  archive : String,
) -> Result[Unit, PackageError] {
  match result {
    Err(error) =>
      match cleanup {
        Ok(_) => Err(error)
        Err(cleanup_error) =>
          Err(
            CommandError(
              "macOS notarization failed and the temporary archive could not be removed: " +
              archive +
              "; notarization error: " +
              @debug.render(@debug.to_repr(error)) +
              "; cleanup error: " +
              @debug.render(@debug.to_repr(cleanup_error)),
            ),
          )
      }
    Ok(_) => cleanup
  }
}

///|
async fn submit_macos_notarization(
  app : String,
  archive : String,
  profile : String,
) -> Result[Unit, PackageError] {
  let zip_code = @process.run("ditto", [
    "-c", "-k", "--keepParent", app, archive,
  ]) catch {
    error =>
      return Err(
        CommandError(
          "failed to create notarization archive: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  guard zip_code == 0 else {
    return Err(
      CommandError(
        "notarization archive command exited with code " + zip_code.to_string(),
      ),
    )
  }
  let submit_code = @process.run("xcrun", [
    "notarytool", "submit", archive, "--keychain-profile", profile, "--wait",
  ]) catch {
    error =>
      return Err(
        CommandError(
          "failed to submit notarization: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  guard submit_code == 0 else {
    return Err(
      CommandError(
        "notarytool submit exited with code " + submit_code.to_string(),
      ),
    )
  }
  let staple_code = @process.run("xcrun", ["stapler", "staple", app]) catch {
    error =>
      return Err(
        CommandError(
          "failed to staple notarization ticket: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  guard staple_code == 0 else {
    return Err(
      CommandError("stapler exited with code " + staple_code.to_string()),
    )
  }
  let validate_code = @process.run("xcrun", ["stapler", "validate", app]) catch {
    error =>
      return Err(
        CommandError(
          "failed to validate notarization ticket: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  guard validate_code == 0 else {
    return Err(
      CommandError(
        "stapler validate exited with code " + validate_code.to_string(),
      ),
    )
  }
  let assess_code = @process.run("spctl", [
    "--assess", "--type", "execute", "--verbose=4", app,
  ]) catch {
    error =>
      return Err(
        CommandError(
          "failed to run Gatekeeper assessment: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if assess_code == 0 {
    Ok(())
  } else {
    Err(
      CommandError(
        "Gatekeeper assessment exited with code " + assess_code.to_string(),
      ),
    )
  }
}

///|
async fn create_zip(
  plan : PackagePlan,
  source : String,
) -> Result[Unit, PackageError] {
  let archive = resolve_path(plan.output, path_basename(source) + ".zip")
  match remove_tree(archive) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let code = if @path.sep == '\\' {
    @process.run("powershell", [
      "-NoProfile", "-Command", "Compress-Archive", "-Path", source, "-DestinationPath",
      archive,
    ]) catch {
      error =>
        return Err(
          CommandError(
            "failed to create zip: " + @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  } else {
    @process.run("ditto", [
      "-c", "-k", "--sequesterRsrc", "--keepParent", source, archive,
    ]) catch {
      error =>
        return Err(
          CommandError(
            "failed to create zip: " + @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  }
  if code == 0 {
    println("Created archive: " + archive)
    Ok(())
  } else {
    Err(CommandError("zip command exited with code " + code.to_string()))
  }
}

///|
fn resolve_package_config_path(
  cwd : String,
  root : String,
  raw : RawPackageOptions,
) -> String? {
  match raw.config_path {
    Some(path) => Some(resolve_path(cwd, path))
    None => {
      let package_config = resolve_path(
        cwd,
        raw.app_package + "/" + default_config_file,
      )
      let cwd_config = resolve_path(cwd, default_config_file)
      let root_config = resolve_path(root, default_config_file)
      if @mbfs.path_exists(package_config) {
        Some(package_config)
      } else if @mbfs.path_exists(cwd_config) {
        Some(cwd_config)
      } else if @mbfs.path_exists(root_config) {
        Some(root_config)
      } else {
        None
      }
    }
  }
}

///|
fn find_project_root_from(start : String) -> String {
  for dir = start; dir != ""; {
    if @mbfs.path_exists(resolve_path(dir, "moon.work")) ||
      @mbfs.path_exists(resolve_path(dir, "moon.mod")) {
      return dir
    }
    let parent = path_parent(dir)
    if parent == dir {
      return start
    }
    continue parent
  }
  start
}

///|
fn find_workspace_root_from(start : String) -> String {
  let mut module_root : String? = None
  for dir = start; dir != ""; {
    if @mbfs.path_exists(resolve_path(dir, "moon.work")) {
      return dir
    }
    if module_root is None && @mbfs.path_exists(resolve_path(dir, "moon.mod")) {
      module_root = Some(dir)
    }
    let parent = path_parent(dir)
    if parent == dir {
      return module_root.unwrap_or(start)
    }
    continue parent
  }
  module_root.unwrap_or(start)
}

///|
fn path_parent(path : String) -> String {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  let slash = normalized.rev_find("/")
  let backslash = normalized.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      normalized.unsafe_substring(start=0, end=index).to_string()
    _ => normalized.to_string()
  }
}

///|
fn path_is_file(path : String) -> Bool {
  @mbfs.is_file(path) catch {
    _ => false
  }
}

///|
fn path_is_dir(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn package_path_is_absolute(path : String) -> Bool {
  if @path.sep == '\\' {
    if path.has_prefix("\\") {
      return true
    }
    guard path.length() >= 3 else { return false }
    let drive = path[0]
    ((drive >= 65 && drive <= 90) || (drive >= 97 && drive <= 122)) &&
    path[1] == ':' &&
    path[2] == '\\'
  } else {
    path.has_prefix("/")
  }
}

///|
fn resolve_path(base : String, child : String) -> String {
  let base = if @path.sep == '\\' {
    base.replace_all(old="/", new="\\")
  } else {
    base.replace_all(old="\\", new="/")
  }
  let child = if @path.sep == '\\' {
    child.replace_all(old="/", new="\\")
  } else {
    child.replace_all(old="\\", new="/")
  }
  let path : @path.Path = child
  if package_path_is_absolute(child) {
    path.normalize().resolve().to_string()
  } else {
    let combined = if base == "" {
      child
    } else if base.has_suffix(@path.sep.to_string()) {
      base + child
    } else {
      base + @path.sep.to_string() + child
    }
    @path.Path(combined).normalize().resolve().to_string()
  }
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}
