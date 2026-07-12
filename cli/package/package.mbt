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
  app_package : String
  config_path : String
  product_name : String
  identifier : String
  version : String
  targets : Array[String]
  output : String
  build : Bool
  base_dir : String
  frontend_dist : String?
  entry_path : String?
  resources : Array[String]
  icons : Array[String]
  sign : Bool
  notarize : Bool
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
    Err(message) => return Err(CommandError(message))
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
  let targets = if raw.targets.length() > 0 {
    copy_strings(raw.targets)
  } else if bundle.targets.length() > 0 {
    copy_strings(bundle.targets)
  } else {
    ["app", "zip"]
  }
  let output = match raw.output {
    Some(output) => resolve_path(project.base_dir(), output)
    None => bundle.output()
  }
  let frontend_dist = match project.frontend() {
    Some(frontend) => frontend.dist()
    None => None
  }
  let entry_path = match project.entry() {
    File(path) | Asset(path) => Some(path)
    Html(_) | Url(_) => None
  }
  Ok(PackagePlan::{
    root: find_project_root_from(project.base_dir()),
    workspace_root: find_workspace_root_from(project.base_dir()),
    app_package: raw.app_package,
    config_path,
    product_name: metadata.product_name,
    identifier,
    version,
    targets,
    output,
    build: raw.build,
    base_dir: project.base_dir(),
    frontend_dist,
    entry_path,
    resources: copy_strings(bundle.resources),
    icons: copy_strings(bundle.icon),
    sign: raw.sign,
    notarize: raw.notarize,
  })
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
          "release executable not found under " +
          resolve_path(plan.workspace_root, "_build/native/release/build"),
        ),
      )
  }
  let runtime = match read_active_runtime(plan.workspace_root) {
    Ok(runtime) => runtime
    Err(error) => return Err(error)
  }
  if @path.sep == '\\' {
    stage_windows_portable(plan, executable, runtime)
  } else if @mbfs.path_exists(
      "/System/Library/CoreServices/SystemVersion.plist",
    ) {
    stage_macos_app(plan, executable, runtime)
  } else {
    Err(CommandError("proton package currently supports macOS and Windows"))
  }
}

///|
async fn run_release_build(plan : PackagePlan) -> Result[Unit, PackageError] {
  let args = [plan.app_package, "--config", plan.config_path, "--", "--release"]
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
  let root = resolve_path(plan.workspace_root, "_build/native/release/build")
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
fn read_active_runtime(root : String) -> Result[String, PackageError] {
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
    Object(fields) =>
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
  let app = resolve_path(plan.output, plan.product_name + ".app")
  let contents = resolve_path(app, "Contents")
  let macos = resolve_path(contents, "MacOS")
  let resources = resolve_path(contents, "Resources")
  let frameworks = resolve_path(contents, "Frameworks")
  let executable_name = package_executable_name(plan.product_name)
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
  println("Packaged macOS app: " + app)
  if plan.targets.contains("zip") {
    match create_zip(plan, app) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
async fn stage_windows_portable(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Result[Unit, PackageError] {
  let output = resolve_path(
    plan.output,
    package_executable_name(plan.product_name),
  )
  match remove_tree(output) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match ensure_dir(output) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match copy_tree(resolve_path(runtime, "bin"), output) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let runtime_resources = resolve_path(runtime, "Resources")
  if @mbfs.path_exists(runtime_resources) {
    match copy_tree(runtime_resources, resolve_path(output, "Resources")) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match
    copy_file(
      executable,
      resolve_path(output, package_executable_name(plan.product_name) + ".exe"),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match copy_file(plan.config_path, resolve_path(output, "moon.proton")) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match stage_project_inputs(plan, output) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match write_package_manifest(plan, output, "windows-portable") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if plan.sign {
    match sign_windows_portable(plan, output) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  println("Packaged Windows portable app: " + output)
  if plan.targets.contains("zip") {
    match create_zip(plan, output) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
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
  let copied : Map[String, Bool] = {}
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
  for icon in plan.icons {
    if icon.to_lower().has_suffix(".icns") {
      guard @mbfs.path_exists(icon) else {
        return Err(CommandError("macOS icon is missing: " + icon))
      }
      return copy_file(icon, resolve_path(resources, "AppIcon.icns"))
    }
  }
  Ok(())
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
  @async_fs.mkdir(path, recursive=true) catch {
    error =>
      return Err(
        CommandError(
          "failed to create directory " +
          path +
          ": " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
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
  if @path.sep != '\\' {
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
    @process.run("robocopy", [
      source, destination, "/E", "/COPY:DAT", "/DCOPY:DAT", "/NFL", "/NDL",
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
  } else {
    @process.run("ditto", [source, destination]) catch {
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
    #|<key>CFBundleIconFile</key><string>AppIcon</string>
    #|<key>CFBundleName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{VERSION}}</string>
    #|<key>LSMinimumSystemVersion</key><string>12.0</string>
    #|<key>NSHighResolutionCapable</key><true/>
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{PRODUCT}}", new=xml_escape(plan.product_name))
  .replace_all(old="{{EXECUTABLE}}", new=xml_escape(executable))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(plan.identifier))
  .replace_all(old="{{VERSION}}", new=xml_escape(plan.version))
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
    #|<key>CFBundleShortVersionString</key><string>{{VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{VERSION}}</string>
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{PRODUCT}}", new=xml_escape(plan.product_name))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(plan.identifier))
  .replace_all(old="{{VERSION}}", new=xml_escape(plan.version))
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
  let contents = resolve_path(app, "Contents")
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
  for
    target in [
      cef_framework,
      resolve_path(runtime_bin, "libEGL.dylib"),
      resolve_path(runtime_bin, "libGLESv2.dylib"),
      resolve_path(runtime_bin, "libvk_swiftshader.dylib"),
      resolve_path(runtime_bin, "cef_process"),
      libproton,
      helper,
      main,
      app,
    ] {
    guard @mbfs.path_exists(target) else { continue }
    match
      codesign_target(
        identity,
        target,
        runtime_options=target == app,
        deep=target.has_suffix(".framework"),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let code = @process.run("codesign", [
    "--verify", "--deep", "--strict", "--verbose=2", app,
  ]) catch {
    error =>
      return Err(
        CommandError(
          "failed to verify macOS signature: " +
          @debug.render(@debug.to_repr(error)),
        ),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(
      CommandError("codesign verification exited with code " + code.to_string()),
    )
  }
}

///|
async fn codesign_target(
  identity : String,
  target : String,
  runtime_options~ : Bool,
  deep~ : Bool,
) -> Result[Unit, PackageError] {
  let args : Array[String] = ["--force", "--timestamp", "--sign", identity]
  if deep {
    args.push("--deep")
  }
  if runtime_options {
    args.push("--options")
    args.push("runtime")
  }
  match @sys.get_env_var("PROTON_MACOS_ENTITLEMENTS") {
    Some(path) if path.trim().to_owned() != "" && runtime_options => {
      args.push("--entitlements")
      args.push(path.trim().to_owned())
    }
    _ => ()
  }
  args.push(target)
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
async fn notarize_macos_app(
  plan : PackagePlan,
  app : String,
) -> Result[Unit, PackageError] {
  let profile = match @sys.get_env_var("PROTON_NOTARY_PROFILE") {
    Some(profile) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    _ => return Err(CommandError("--notarize requires PROTON_NOTARY_PROFILE"))
  }
  let archive = resolve_path(plan.output, path_basename(app) + ".notary.zip")
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
    return Err(CommandError("failed to create notarization archive"))
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
    return Err(CommandError("notarytool submit failed"))
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
  if staple_code == 0 {
    Ok(())
  } else {
    Err(CommandError("stapler failed"))
  }
}

///|
async fn sign_windows_portable(
  plan : PackagePlan,
  output : String,
) -> Result[Unit, PackageError] {
  let certificate = match @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE") {
    Some(path) if path.trim().to_owned() != "" => path.trim().to_owned()
    _ =>
      return Err(
        CommandError("--sign requires PROTON_WINDOWS_CERTIFICATE on Windows"),
      )
  }
  let password = @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE_PASSWORD").unwrap_or(
    "",
  )
  let timestamp = @sys.get_env_var("PROTON_WINDOWS_TIMESTAMP_URL").unwrap_or(
    "http://timestamp.digicert.com",
  )
  let executable = resolve_path(
    output,
    package_executable_name(plan.product_name) + ".exe",
  )
  let helper = resolve_path(output, "cef_process.exe")
  let proton = resolve_path(output, "proton.dll")
  for target in [helper, proton, executable] {
    guard @mbfs.path_exists(target) else { continue }
    let args : Array[String] = ["sign", "/fd", "SHA256", "/f", certificate]
    if password != "" {
      args.push("/p")
      args.push(password)
    }
    args.push("/tr")
    args.push(timestamp)
    args.push("/td")
    args.push("SHA256")
    args.push(target)
    let code = @process.run("signtool", args) catch {
      error =>
        return Err(
          CommandError(
            "failed to run signtool: " + @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    guard code == 0 else {
      return Err(
        CommandError(
          "signtool exited with code " + code.to_string() + ": " + target,
        ),
      )
    }
  }
  Ok(())
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
fn resolve_path(base : String, child : String) -> String {
  let path : @path.Path = child
  if path.is_absolute() {
    path.normalize().resolve().to_string()
  } else {
    @path.Path(base).join(child).normalize().resolve().to_string()
  }
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}
