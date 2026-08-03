///|
let default_package = "app"

///|
let default_config_file = "moon.proton"

///|
struct RawPackageOptions {
  app_package : String?
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
  update_revision : UInt64
  targets : Array[String]
  output : String
  build : Bool
  base_dir : String
  frontend_dist : String?
  entry_paths : Array[String]
  resources : Array[String]
  icons : Array[String]
  url_schemes : Array[String]
  document_types : Array[@proton_config.ProjectDocumentType]
  macos_icon : String?
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
priv struct StagedArtifact {
  staging : String
  destination : String
}

///|
struct MacosCodeSignTarget {
  path : String
  runtime_options : Bool
  deep : Bool
} derive(Debug, Eq)

///|
priv struct MacosHelperSpec {
  bundle_name : String
  executable_name : String
  bundle_identifier : String
}

///|
/// Returns the declarative `proton_cli package` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "package",
    about="Package a Proton application",
    flags=[
      FlagArg("no-build", about="Reuse an existing release build"),
      FlagArg("dry-run", about="Print the resolved package plan"),
      FlagArg("sign", about="Sign the packaged application"),
      FlagArg(
        "notarize",
        about="Sign, notarize, and staple a macOS application",
      ),
    ],
    options=[
      OptionArg("package", about="MoonBit application package"),
      OptionArg("config", about="Proton project config"),
      OptionArg(
        "target",
        action=Append,
        about="Package target (app, zip, or macOS dmg); may be repeated",
      ),
      OptionArg("output", about="Output directory"),
      OptionArg(
        "updater-base-url",
        about="Emit update metadata with artifacts served from this https base URL",
      ),
      OptionArg(
        "updater-published-at",
        about="Publication instant for the manifest fragment (YYYY-MM-DDTHH:MM:SSZ)",
      ),
      OptionArg(
        "updater-revision",
        allow_hyphen_values=true,
        about="Monotonic release sequence embedded in the app and signed manifest",
      ),
    ],
  )
}

///|
/// Runs the package workflow from parsed command matches.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  let raw = package_options_from_matches(matches)
  let cwd = @path.Path(cwd).resolve().to_string()
  let root = @fsutil.find_project_root_from(cwd)
  let config_path = match resolve_package_config_path(cwd, root, raw) {
    Some(path) => path
    None => raise PackageConfigError::NotFound(path="moon.proton")
  }
  let config_text = @async_fs.read_file(config_path).text() catch {
    error =>
      raise PackageConfigError::Invalid(
        path=config_path,
        error=@proton_config.ProjectConfigError::FileRead(
          path=config_path,
          detail=@debug.render(Repr(error)),
        ),
      )
  }
  let loaded = @proton_config.load_project_config_from_text(
    config_text,
    @fsutil.path_parent(config_path),
    name=config_path,
  ) catch {
    error => raise PackageConfigError::Invalid(path=config_path, error~)
  }
  let project = loaded.config()
  let updater_base_url = @cli_args.value(matches, "updater-base-url")
  let update_revision = updater_revision_from_matches(matches, updater_base_url)
  let plan = build_package_plan(raw, config_path, project, update_revision)
  print_package_plan(plan, raw.dry_run)
  if raw.dry_run {
    return
  }
  execute_package_plan(plan)
  match updater_base_url {
    Some(base_url) =>
      write_updater_metadata(
        plan,
        base_url,
        match @cli_args.value(matches, "updater-published-at") {
          Some(published_at) => published_at
          None => raise MissingPublishedAt
        },
      )
    None => ()
  }
}

///|
fn updater_revision_from_matches(
  matches : @argparse.Matches,
  base_url : String?,
) -> UInt64 raise UpdaterMetadataError {
  match @cli_args.value(matches, "updater-revision") {
    None => {
      guard base_url is None else { raise MissingRevision }
      0UL
    }
    Some(value) => {
      let revision = @string.parse_uint64(value[:]) catch {
        _ => raise InvalidRevision(value~)
      }
      guard revision > 0UL else { raise InvalidRevision(value~) }
      revision
    }
  }
}

///|
fn package_options_from_matches(
  matches : @argparse.Matches,
) -> RawPackageOptions raise PackageUsageError {
  let targets = @cli_args.values(matches, "target")
  for target in targets {
    validate_package_target(target)
  }
  let notarize = @cli_args.flag(matches, "notarize")
  RawPackageOptions::{
    app_package: @cli_args.value(matches, "package"),
    config_path: @cli_args.value(matches, "config"),
    targets,
    output: @cli_args.value(matches, "output"),
    build: !@cli_args.flag(matches, "no-build"),
    dry_run: @cli_args.flag(matches, "dry-run"),
    sign: @cli_args.flag(matches, "sign") || notarize,
    notarize,
  }
}

///|
fn validate_package_target(target : String) -> Unit raise PackageUsageError {
  if target != "app" && target != "zip" && target != "dmg" {
    raise UnsupportedTarget(target~)
  }
}

///|
async fn build_package_plan(
  raw : RawPackageOptions,
  config_path : String,
  project : @proton_config.ProjectConfig,
  update_revision : UInt64,
) -> PackagePlan {
  let bundle = match project.bundle() {
    Some(bundle) if bundle.active() => bundle
    Some(_) => raise PackageConfigError::BundleInactive
    None => raise PackageConfigError::BundleMissing
  }
  let metadata = project.metadata()
  let product_name = validate_product_name(metadata.product_name)
  let identifier = match metadata.identifier {
    Some(identifier) => identifier
    None => raise PackageConfigError::MissingField(field="identifier")
  }
  let version = match metadata.version {
    Some(version) => version
    None => raise PackageConfigError::MissingField(field="moon.mod version")
  }
  let identifier = validate_bundle_identifier(identifier)
  let version = version.trim().to_owned()
  guard version != "" else {
    raise PackageConfigError::MissingField(field="moon.mod version")
  }
  let macos_host = is_macos_host()
  let (macos_version, bundle_version) = if macos_host {
    validate_macos_version(version)
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
  if targets.contains("dmg") && !macos_host {
    raise PackagePlanError::UnsupportedTargetForPlatform(
      target="dmg",
      platform=@cef.current_platform_id(),
    )
  }
  let base_dir = @fsutil.resolve_path(project.base_dir(), ".")
  let backend = project.backend()
  let backend_root = match backend {
    Some(backend) => @fsutil.resolve_path(base_dir, backend.path())
    None => @fsutil.find_project_root_from(base_dir)
  }
  let app_package = match raw.app_package {
    Some(app_package) => app_package
    None =>
      match backend {
        Some(backend) => backend.app_package()
        None => default_package
      }
  }
  let output = match raw.output {
    Some(output) => @fsutil.resolve_path(base_dir, output)
    None => @fsutil.resolve_path(base_dir, bundle.output())
  }
  let frontend_dist = match project.frontend() {
    Some(frontend) => frontend.dist()
    None => None
  }
  let entry_paths : Array[String] = []
  for entry in project.entries() {
    match entry {
      File(path) | Asset(path) => entry_paths.push(path)
      Html(_) | Url(_) => ()
    }
  }
  let workspace_root = find_workspace_root_from(base_dir)
  PackagePlan::{
    root: backend_root,
    workspace_root,
    build_target_dir: package_build_target_dir(workspace_root, identifier),
    app_package,
    config_path,
    product_name,
    identifier,
    version,
    macos_version,
    bundle_version,
    update_revision,
    targets,
    output,
    build: raw.build,
    base_dir,
    frontend_dist,
    entry_paths,
    resources: copy_strings(bundle.resources),
    icons: copy_strings(bundle.icon),
    url_schemes: copy_strings(bundle.url_schemes),
    document_types: bundle.document_types.copy(),
    macos_icon: first_macos_icon(bundle.icon),
    sign: raw.sign,
    notarize: raw.notarize,
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
fn validate_bundle_identifier(value : String) -> String raise PackagePlanError {
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
fn validate_macos_version(
  value : String,
) -> (String, String) raise PackagePlanError {
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
    raise InvalidVersion(
      version=core,
      reason="macOS version must contain one to three numeric components",
    )
  }
  let normalized : Array[String] = []
  for component in components {
    guard component.length() > 0 else {
      raise InvalidVersion(version=core, reason="contains an empty component")
    }
    for char in component {
      guard char.is_ascii_digit() else {
        raise InvalidVersion(version=core, reason="components must be numeric")
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
      validate_bundle_version(build.trim().to_owned())
    _ => short_version
  }
  (short_version, bundle_version)
}

///|
fn validate_bundle_version(value : String) -> String raise PackagePlanError {
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 1 && components.length() <= 3 else {
    raise InvalidVersion(
      version=value,
      reason="PROTON_MACOS_BUILD_NUMBER must contain one to three numeric components",
    )
  }
  for component in components {
    guard component.length() > 0 else {
      raise InvalidVersion(
        version=value,
        reason="PROTON_MACOS_BUILD_NUMBER contains an empty component",
      )
    }
    for char in component {
      guard char.is_ascii_digit() else {
        raise InvalidVersion(
          version=value,
          reason="PROTON_MACOS_BUILD_NUMBER components must be numeric",
        )
      }
    }
  }
  value
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
fn release_project_config_text(source : String) -> String {
  let (ast, reports) = @proton_config.parse_moon_proton(source)
  guard reports.length() == 0 else { return source }
  match ast {
    Obj(fields, _) =>
      for field in fields {
        if field.key == "debug" {
          match field.value {
            Bool(false, _) => return source
            Bool(true, loc) =>
              return replace_string_range(
                source,
                loc.start.cnum,
                loc.end.cnum,
                "false",
              )
            _ => return source
          }
        }
      }
    _ => ()
  }
  source
}

///|
fn replace_string_range(
  source : String,
  start : Int,
  end : Int,
  replacement : String,
) -> String {
  let output = StringBuilder::new(
    size_hint=source.length() - (end - start) + replacement.length(),
  )
  for index, char in source {
    if index == start {
      output.write_string(replacement)
    }
    if index < start || index >= end {
      output.write_char(char)
    }
  }
  if start == source.length() {
    output.write_string(replacement)
  }
  output.to_string()
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
  println("  update revision: " + plan.update_revision.to_string())
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
async fn execute_package_plan(plan : PackagePlan) -> Unit {
  // Resolve the active runtime before any build work so a missing
  // `proton_cli cef setup` fails fast instead of after a full release build.
  let runtime = read_active_runtime(plan.workspace_root)
  if plan.build {
    run_release_build(plan)
  }
  let executable = match find_release_executable(plan) {
    Some(path) => path
    None =>
      raise PackagePlanError::MissingExecutable(path=plan.build_target_dir)
  }
  if @path.sep == '\\' {
    stage_windows_portable(plan, executable, runtime)
  } else if is_macos_host() {
    stage_macos_app(plan, executable, runtime)
  } else {
    raise PackagePlanError::UnsupportedPlatform
  }
}

///|
async fn is_macos_host() -> Bool {
  @fsutil.path_exists("/System/Library/CoreServices/SystemVersion.plist")
}

///|
async fn run_release_build(plan : PackagePlan) -> Unit {
  let moon_args = ["--release", "--target-dir", plan.build_target_dir]
  let old_rpath = @sys.get_env_var("PROTON_PACKAGE_RPATH")
  if @path.sep != '\\' {
    @sys.set_env_var(
      "PROTON_PACKAGE_RPATH", "@executable_path/../Resources/proton/lib",
    )
  }
  defer restore_package_env("PROTON_PACKAGE_RPATH", old_rpath)
  @build.run_release(plan.root, plan.app_package, plan.config_path, moon_args)
}

///|
fn restore_package_env(name : String, value : String?) -> Unit {
  match value {
    Some(value) => @sys.set_env_var(name, value)
    None => @sys.unset_env_var(name)
  }
}

///|
async fn find_release_executable(plan : PackagePlan) -> String? {
  let root = @fsutil.resolve_path(plan.build_target_dir, "native/release/build")
  let package_name = path_basename(plan.app_package)
  find_named_file(root, package_name + ".exe")
}

///|
async fn find_named_file(root : String, name : String) -> String? {
  guard @fsutil.path_exists(root) else { return None }
  if @fsutil.path_is_file(root) {
    return if path_basename(root) == name { Some(root) } else { None }
  }
  let entries = @async_fs.readdir(
    root,
    include_hidden=true,
    include_special=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  for entry in entries {
    match find_named_file(@fsutil.resolve_path(root, entry), name) {
      Some(path) => return Some(path)
      None => ()
    }
  }
  None
}

///|
async fn read_active_runtime(root : String) -> String {
  match @sys.get_env_var("PROTON_NATIVE_DIST") {
    Some(value) if value.trim().to_owned() != "" =>
      return require_runtime(
        @fsutil.resolve_path(root, value.trim().to_owned()),
      )
    _ => ()
  }
  let manifest_path = @fsutil.resolve_path(root, ".proton/runtime.json")
  let text = @async_fs.read_file(manifest_path).text() catch {
    _ => raise PackageRuntimeError::ManifestMissing(path=manifest_path)
  }
  let json = @json.parse(text) catch {
    error =>
      raise PackageRuntimeError::ManifestInvalid(
        path=manifest_path,
        detail=@debug.render(Repr(error)),
      )
  }
  match json {
    Object(fields) => {
      let platform = match fields.get("platform") {
        Some(String(platform)) => platform
        _ =>
          raise PackageRuntimeError::ManifestField(
            path=manifest_path,
            field="platform",
          )
      }
      let expected_platform = @cef.current_platform_id()
      guard platform == expected_platform else {
        raise PackageRuntimeError::PlatformMismatch(
          expected=expected_platform,
          actual=platform,
        )
      }
      match fields.get("dist") {
        Some(String(dist)) => require_runtime(@fsutil.resolve_path(root, dist))
        _ =>
          raise PackageRuntimeError::ManifestField(
            path=manifest_path,
            field="dist",
          )
      }
    }
    _ =>
      raise PackageRuntimeError::ManifestInvalid(
        path=manifest_path,
        detail="root must be an object",
      )
  }
}

///|
fn package_build_target_dir(
  workspace_root : String,
  identifier : String,
) -> String {
  @fsutil.resolve_path(
    workspace_root,
    "target/proton-package-build/" + package_executable_name(identifier),
  )
}

///|
async fn require_runtime(path : String) -> String {
  if @fsutil.path_is_dir(path) {
    path
  } else {
    raise DirectoryMissing(path~)
  }
}

///|
async fn stage_macos_app(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  stage_macos_app_impl(plan, executable, runtime) catch {
    error => {
      for
        path in [
          macos_staging_root_path(plan),
          macos_dmg_staging_path(plan),
          macos_dmg_root_path(plan),
          macos_zip_staging_path(plan),
        ] {
        remove_tree(path) catch {
          _ => ()
        }
      }
      raise error
    }
  }
}

///|
async fn stage_macos_app_impl(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  let final_app = @fsutil.resolve_path(plan.output, plan.product_name + ".app")
  let executable_name = package_executable_name(plan.product_name)
  let app = macos_staging_app_path(plan)
  let contents = @fsutil.resolve_path(app, "Contents")
  let macos = @fsutil.resolve_path(contents, "MacOS")
  let resources = @fsutil.resolve_path(contents, "Resources")
  let frameworks = @fsutil.resolve_path(contents, "Frameworks")
  remove_tree(macos_staging_root_path(plan))
  for dir in [macos, resources, frameworks] {
    ensure_dir(dir)
  }
  copy_file(executable, @fsutil.resolve_path(macos, executable_name))
  copy_tree(runtime, @fsutil.resolve_path(resources, "proton"))
  stage_release_project_config(
    plan.config_path,
    @fsutil.resolve_path(resources, "moon.proton"),
  )
  stage_project_inputs(plan, resources)
  stage_macos_icon(plan, resources)
  let helper_source = @fsutil.resolve_path(runtime, "bin/cef_process")
  guard @fsutil.path_exists(helper_source) else {
    raise PackageRuntimeError::HelperMissing(path=helper_source)
  }
  for helper in macos_helper_specs(plan.product_name, plan.identifier) {
    let helper_app = @fsutil.resolve_path(
      frameworks,
      helper.bundle_name + ".app",
    )
    let helper_macos = @fsutil.resolve_path(helper_app, "Contents/MacOS")
    let helper_executable = @fsutil.resolve_path(
      helper_macos,
      helper.executable_name,
    )
    ensure_dir(helper_macos)
    copy_file(helper_source, helper_executable)
    write_text(
      @fsutil.resolve_path(helper_app, "Contents/Info.plist"),
      helper_info_plist(plan, helper),
    )
    add_macos_rpath(
      helper_executable, "@loader_path/../../../../Resources/proton/lib",
    )
  }
  write_text(
    @fsutil.resolve_path(contents, "Info.plist"),
    macos_info_plist(plan, executable_name),
  )
  write_package_manifest(plan, resources, "macos-app")
  if plan.sign {
    sign_macos_app(plan, app, executable_name)
  } else {
    sign_macos_app_adhoc(plan, app, executable_name)
  }
  let dmg = if plan.targets.contains("dmg") {
    Some(create_macos_dmg(plan, app))
  } else {
    None
  }
  if plan.notarize {
    match dmg {
      Some(dmg) => notarize_macos_dmg(app, dmg)
      None => notarize_macos_app(plan, app)
    }
  }
  let zip = if plan.targets.contains("zip") {
    let staging = macos_zip_staging_path(plan)
    create_zip(app, staging)
    Some(staging)
  } else {
    None
  }
  let artifacts = [StagedArtifact::{ staging: app, destination: final_app }]
  match dmg {
    Some(dmg) =>
      artifacts.push(StagedArtifact::{
        staging: dmg,
        destination: macos_dmg_path(plan),
      })
    None => ()
  }
  match zip {
    Some(zip) =>
      artifacts.push(StagedArtifact::{
        staging: zip,
        destination: macos_zip_path(plan),
      })
    None => ()
  }
  promote_staged_artifacts(artifacts)
  remove_tree(macos_staging_root_path(plan)) catch {
    _ => ()
  }
  println("Packaged macOS app: " + final_app)
  match dmg {
    Some(_) => {
      let final_dmg = macos_dmg_path(plan)
      println("Created disk image: " + final_dmg)
    }
    None => ()
  }
  if zip is Some(_) {
    println("Created archive: " + macos_zip_path(plan))
  }
}

///|
fn macos_staging_root_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging",
  )
}

///|
fn macos_staging_app_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    macos_staging_root_path(plan),
    plan.product_name + ".app",
  )
}

///|
fn macos_zip_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(plan.output, plan.product_name + ".app.zip")
}

///|
fn macos_zip_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging.app.zip",
  )
}

///|
async fn recover_staged_artifact_backup(destination : String) -> Unit {
  let backup = destination + ".backup"
  if @fsutil.path_exists(backup) {
    if @fsutil.path_exists(destination) {
      remove_tree(backup)
    } else {
      @async_fs.rename(backup, destination) catch {
        error =>
          raise PackageFileSystemError::Copy(
            source=backup,
            destination~,
            detail="restore failed: " + @debug.render(Repr(error)),
          )
      }
    }
  }
}

///|
async fn rename_staged_artifact(source : String, destination : String) -> Unit {
  @async_fs.rename(source, destination) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise PackageFileSystemError::Copy(
        source~,
        destination~,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
async fn promote_staged_artifacts(artifacts : Array[StagedArtifact]) -> Unit {
  guard artifacts.length() > 0 else { return }
  for artifact in artifacts {
    recover_staged_artifact_backup(artifact.destination)
  }

  let backed_up : Array[String] = []
  let promoted : Array[String] = []
  try {
    for artifact in artifacts {
      if @fsutil.path_exists(artifact.destination) {
        rename_staged_artifact(
          artifact.destination,
          artifact.destination + ".backup",
        )
        backed_up.push(artifact.destination)
      }
    }
    for artifact in artifacts {
      rename_staged_artifact(artifact.staging, artifact.destination)
      promoted.push(artifact.destination)
    }
  } catch {
    error => {
      let rollback_failures : Array[String] = []
      let promoted_count = promoted.length()
      for offset in 0..<promoted_count {
        let destination = promoted[promoted_count - offset - 1]
        remove_tree(destination) catch {
          rollback_error =>
            rollback_failures.push(
              "remove " +
              destination +
              ": " +
              @debug.render(Repr(rollback_error)),
            )
        }
      }
      let backup_count = backed_up.length()
      for offset in 0..<backup_count {
        let destination = backed_up[backup_count - offset - 1]
        let backup = destination + ".backup"
        @async_fs.rename(backup, destination) catch {
          rollback_error =>
            rollback_failures.push(
              "restore " +
              destination +
              ": " +
              @debug.render(Repr(rollback_error)),
            )
        }
      }
      if @async.is_being_cancelled() {
        raise error
      }
      if rollback_failures.length() > 0 {
        raise PackageFileSystemError::Copy(
          source="staged package artifacts",
          destination=artifacts[0].destination,
          detail=@debug.render(Repr(error)) +
            "; rollback failed: " +
            rollback_failures.join("; "),
        )
      }
      raise error
    }
  }

  for destination in backed_up {
    remove_tree(destination + ".backup") catch {
      _ => ()
    }
  }
}

///|
async fn stage_project_inputs(plan : PackagePlan, destination : String) -> Unit {
  let inputs : Array[String] = []
  match plan.frontend_dist {
    Some(path) => inputs.push(path)
    None => ()
  }
  for path in plan.entry_paths {
    inputs.push(path)
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
        raise PackagePlanError::UnsupportedResourceGlob(path=input)
      None => input
    }
    guard @fsutil.path_exists(source) else {
      raise PackagePlanError::MissingInput(path=input)
    }
    let relative = match relative_to_base(plan.base_dir, source) {
      Some(relative) => relative
      None => raise PackagePlanError::InputOutsideProject(path=input)
    }
    copy_tree(source, @fsutil.resolve_path(destination, relative))
  }
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
async fn stage_macos_icon(plan : PackagePlan, resources : String) -> Unit {
  match plan.macos_icon {
    None => ()
    Some(icon) => {
      guard @fsutil.path_exists(icon) else {
        raise PackagePlanError::MissingIcon(path=icon)
      }
      copy_file(icon, @fsutil.resolve_path(resources, "AppIcon.icns"))
    }
  }
}

///|
fn relative_to_base(base : String, path : String) -> String? {
  let base = normalize_slashes(@fsutil.resolve_path(base, "."))
  let path = normalize_slashes(@fsutil.resolve_path(base, path))
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
async fn ensure_dir(path : String) -> Unit {
  guard !@fsutil.path_exists(path) else { return }
  let parent = @fsutil.path_parent(path)
  if parent != path && !@fsutil.path_exists(parent) {
    ensure_dir(parent)
  }
  @async_fs.mkdir(path) catch {
    error => {
      if @fsutil.path_exists(path) {
        return
      }
      raise PackageFileSystemError::CreateDirectory(
        path~,
        detail=@debug.render(Repr(error)),
      )
    }
  }
}

///|
async fn remove_tree(path : String) -> Unit {
  guard @fsutil.path_exists(path) else { return }
  if @fsutil.path_is_file(path) {
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
  ensure_dir(@fsutil.path_parent(destination))
  if is_macos_host() {
    let code = @process.run("ditto", [source, destination]) catch {
      error =>
        raise PackageFileSystemError::Copy(
          source~,
          destination~,
          detail=@debug.render(Repr(error)),
        )
    }
    if code != 0 {
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
  if @fsutil.path_is_file(source) {
    return copy_file(source, destination)
  }
  guard @fsutil.path_is_dir(source) else {
    raise PackageFileSystemError::InvalidSource(path=source)
  }
  ensure_dir(@fsutil.path_parent(destination))
  let code = if @path.sep == '\\' {
    let (code, _) = @process.collect_output_merged("robocopy", [
      source, destination, "/E", "/COPY:DAT", "/DCOPY:DAT", "/NFL", "/NDL", "/NJH",
      "/NJS", "/NP", "/R:2", "/W:1",
    ]) catch {
      error =>
        raise PackageFileSystemError::Copy(
          source~,
          destination~,
          detail=@debug.render(Repr(error)),
        )
    }
    code
  } else if is_macos_host() {
    let (code, _) = @process.collect_output_merged("ditto", [
      source, destination,
    ]) catch {
      error =>
        raise PackageFileSystemError::Copy(
          source~,
          destination~,
          detail=@debug.render(Repr(error)),
        )
    }
    code
  } else {
    let (code, _) = @process.collect_output_merged("cp", [
      "-R", source, destination,
    ]) catch {
      error =>
        raise PackageFileSystemError::Copy(
          source~,
          destination~,
          detail=@debug.render(Repr(error)),
        )
    }
    code
  }
  if code != 0 && !(@path.sep == '\\' && code < 8) {
    raise PackageFileSystemError::Copy(
      source~,
      destination~,
      detail="copy tool exited with code " + code.to_string(),
    )
  }
}

///|
async fn write_text(
  path : String,
  text : String,
) -> Unit raise PackageFileSystemError {
  @async_fs.write_file(path, text, create_mode=CreateOrTruncate) catch {
    error => raise Write(path~, detail=@debug.render(Repr(error)))
  }
}

///|
async fn stage_release_project_config(
  source : String,
  destination : String,
) -> Unit {
  let text = @async_fs.read_file(source).text() catch {
    error =>
      raise PackageFileSystemError::Read(
        path=source,
        detail=@debug.render(Repr(error)),
      )
  }
  write_text(destination, release_project_config_text(text))
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
    #|{{URL_TYPES}}
    #|{{DOCUMENT_TYPES}}
    #|<key>CFBundleName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{MACOS_VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{BUNDLE_VERSION}}</string>
    #|<key>ProtonUpdateRevision</key><string>{{UPDATE_REVISION}}</string>
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
  .replace_all(old="{{UPDATE_REVISION}}", new=plan.update_revision.to_string())
  .replace_all(old="{{ICON}}", new=macos_icon_plist_entry(plan.macos_icon))
  .replace_all(old="{{URL_TYPES}}", new=macos_url_types_plist_entry(plan))
  .replace_all(
    old="{{DOCUMENT_TYPES}}",
    new=macos_document_types_plist_entry(plan.document_types),
  )
}

///|
fn macos_icon_plist_entry(icon : String?) -> String {
  match icon {
    Some(_) => "<key>CFBundleIconFile</key><string>AppIcon</string>"
    None => ""
  }
}

///|
fn macos_url_types_plist_entry(plan : PackagePlan) -> String {
  guard plan.url_schemes.length() > 0 else { return "" }
  let schemes = StringBuilder::new()
  for scheme in plan.url_schemes {
    schemes.write_string("<string>")
    schemes.write_string(xml_escape(scheme))
    schemes.write_string("</string>")
  }
  "<key>CFBundleURLTypes</key><array><dict>" +
  "<key>CFBundleURLName</key><string>" +
  xml_escape(plan.identifier) +
  "</string><key>CFBundleURLSchemes</key><array>" +
  schemes.to_string() +
  "</array></dict></array>"
}

///|
fn macos_document_types_plist_entry(
  document_types : Array[@proton_config.ProjectDocumentType],
) -> String {
  guard document_types.length() > 0 else { return "" }
  let entries = StringBuilder::new()
  for document_type in document_types {
    entries.write_string("<dict><key>CFBundleTypeName</key><string>")
    entries.write_string(xml_escape(document_type.name))
    entries.write_string("</string><key>CFBundleTypeRole</key><string>")
    entries.write_string(xml_escape(document_type.role))
    entries.write_string("</string><key>CFBundleTypeExtensions</key><array>")
    for extension in document_type.extensions {
      entries.write_string("<string>")
      entries.write_string(xml_escape(extension))
      entries.write_string("</string>")
    }
    entries.write_string(
      "</array><key>LSHandlerRank</key><string>Owner</string></dict>",
    )
  }
  "<key>CFBundleDocumentTypes</key><array>" + entries.to_string() + "</array>"
}

///|
fn macos_helper_specs(
  product_name : String,
  identifier : String,
) -> Array[MacosHelperSpec] {
  let base_name = product_name + " Helper"
  let base_identifier = identifier + ".helper"
  [
    MacosHelperSpec::{
      bundle_name: base_name,
      executable_name: base_name,
      bundle_identifier: base_identifier,
    },
    MacosHelperSpec::{
      bundle_name: base_name + " (Alerts)",
      executable_name: base_name + " (Alerts)",
      bundle_identifier: base_identifier + ".alerts",
    },
    MacosHelperSpec::{
      bundle_name: base_name + " (GPU)",
      executable_name: base_name + " (GPU)",
      bundle_identifier: base_identifier + ".gpu",
    },
    MacosHelperSpec::{
      bundle_name: base_name + " (Plugin)",
      executable_name: base_name + " (Plugin)",
      bundle_identifier: base_identifier + ".plugin",
    },
    MacosHelperSpec::{
      bundle_name: base_name + " (Renderer)",
      executable_name: base_name + " (Renderer)",
      bundle_identifier: base_identifier + ".renderer",
    },
  ]
}

///|
fn helper_info_plist(plan : PackagePlan, helper : MacosHelperSpec) -> String {
  let template =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0"><dict>
    #|<key>CFBundleExecutable</key><string>{{EXECUTABLE}}</string>
    #|<key>CFBundleIdentifier</key><string>{{IDENTIFIER}}</string>
    #|<key>CFBundleName</key><string>{{NAME}}</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{MACOS_VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{BUNDLE_VERSION}}</string>
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{EXECUTABLE}}", new=xml_escape(helper.executable_name))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(helper.bundle_identifier))
  .replace_all(old="{{NAME}}", new=xml_escape(helper.bundle_name))
  .replace_all(old="{{MACOS_VERSION}}", new=xml_escape(plan.macos_version))
  .replace_all(old="{{BUNDLE_VERSION}}", new=xml_escape(plan.bundle_version))
}

///|
async fn write_package_manifest(
  plan : PackagePlan,
  destination : String,
  kind : String,
) -> Unit raise PackageFileSystemError {
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
    "url_schemes": Json::array(
      plan.url_schemes.map(fn(scheme) { Json::string(scheme) }),
    ),
    "document_types": Json::array(
      plan.document_types.map(fn(document_type) {
        Json::object({
          "name": Json::string(document_type.name),
          "extensions": Json::array(
            document_type.extensions.map(fn(extension) {
              Json::string(extension)
            }),
          ),
          "role": Json::string(document_type.role),
        })
      }),
    ),
  }).stringify()
  write_text(
    @fsutil.resolve_path(destination, "proton-package.json"),
    json + "\n",
  )
}

///|
async fn add_macos_rpath(binary : String, rpath : String) -> Unit {
  let code = @process.run("install_name_tool", ["-add_rpath", rpath, binary]) catch {
    error =>
      raise PackageToolError::Start(
        tool="install_name_tool",
        detail=@debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise PackageToolError::Exit(tool="install_name_tool", code~, detail=binary)
  }
}

///|
fn required_macos_signing_identity() -> String raise MacosSigningError {
  match @sys.get_env_var("PROTON_MACOS_SIGNING_IDENTITY") {
    Some(identity) if identity.trim().to_owned() != "" =>
      identity.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="--sign requires PROTON_MACOS_SIGNING_IDENTITY with a Developer ID Application identity",
      )
  }
}

///|
async fn sign_macos_app(
  plan : PackagePlan,
  app : String,
  executable_name : String,
) -> Unit {
  let identity = required_macos_signing_identity()
  let is_adhoc = validate_macos_signing_identity(
    identity,
    notarize=plan.notarize,
  )
  sign_macos_app_with_identity(
    plan,
    app,
    executable_name,
    identity,
    allow_untrusted_libraries=is_adhoc,
    verify_developer_id=!is_adhoc,
  )
}

///|
async fn sign_macos_app_adhoc(
  plan : PackagePlan,
  app : String,
  executable_name : String,
) -> Unit {
  sign_macos_app_with_identity(
    plan,
    app,
    executable_name,
    "-",
    allow_untrusted_libraries=true,
    verify_developer_id=false,
  )
}

///|
async fn sign_macos_app_with_identity(
  plan : PackagePlan,
  app : String,
  executable_name : String,
  identity : String,
  allow_untrusted_libraries~ : Bool,
  verify_developer_id~ : Bool,
) -> Unit {
  let contents = @fsutil.resolve_path(app, "Contents")
  let entitlements = resolve_macos_entitlements(app, allow_untrusted_libraries~)
  let main = @fsutil.resolve_path(contents, "MacOS/" + executable_name)
  let cef_framework = @fsutil.resolve_path(
    contents, "Resources/proton/Frameworks/Chromium Embedded Framework.framework",
  )
  let libproton = @fsutil.resolve_path(
    contents, "Resources/proton/lib/libproton.dylib",
  )
  let runtime_bin = @fsutil.resolve_path(contents, "Resources/proton/bin")
  let targets = [
    MacosCodeSignTarget::{
      path: cef_framework,
      runtime_options: false,
      deep: true,
    },
    MacosCodeSignTarget::{
      path: @fsutil.resolve_path(runtime_bin, "libEGL.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: @fsutil.resolve_path(runtime_bin, "libGLESv2.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: @fsutil.resolve_path(runtime_bin, "libvk_swiftshader.dylib"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: @fsutil.resolve_path(runtime_bin, "cef_process"),
      runtime_options: false,
      deep: false,
    },
    MacosCodeSignTarget::{
      path: libproton,
      runtime_options: false,
      deep: false,
    },
  ]
  for helper in macos_helper_specs(plan.product_name, plan.identifier) {
    targets.push(MacosCodeSignTarget::{
      path: @fsutil.resolve_path(
        contents,
        "Frameworks/" + helper.bundle_name + ".app",
      ),
      runtime_options: true,
      deep: false,
    })
  }
  targets.push(MacosCodeSignTarget::{
    path: main,
    runtime_options: true,
    deep: false,
  })
  targets.push(MacosCodeSignTarget::{
    path: app,
    runtime_options: true,
    deep: true,
  })
  require_macos_codesign_targets(targets)
  for target in targets {
    codesign_target(
      identity,
      target.path,
      runtime_options=target.runtime_options,
      deep=target.deep,
      entitlements=Some(entitlements),
    )
  }
  for target in targets {
    verify_macos_codesign_target(target.path, deep=target.deep)
  }
  if verify_developer_id {
    verify_macos_developer_id(app)
  }
}

///|
async fn require_macos_codesign_targets(
  targets : Array[MacosCodeSignTarget],
) -> Unit {
  for target in targets {
    guard @fsutil.path_exists(target.path) else {
      raise MacosSigningError::MissingTarget(path=target.path)
    }
  }
}

///|
fn validate_macos_signing_identity(
  identity : String,
  notarize~ : Bool,
) -> Bool raise MacosSigningError {
  if identity != "-" {
    return false
  }
  if !macos_adhoc_signing_allowed() {
    raise InvalidConfiguration(
      detail="ad-hoc signing is not a release path; set PROTON_MACOS_ALLOW_ADHOC=1 only for local diagnostics",
    )
  }
  if notarize {
    raise InvalidConfiguration(
      detail="--notarize requires a Developer ID Application identity; ad-hoc signing is diagnostic only",
    )
  }
  true
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
async fn verify_macos_developer_id(app : String) -> Unit {
  let (code, output) = @process.collect_output_merged("codesign", [
    "--display", "--verbose=4", app,
  ]) catch {
    error =>
      raise MacosSigningError::Verification(
        detail="failed to inspect signing authority: " +
          @debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::Verification(
      detail="failed to inspect signing authority",
    )
  }
  let text = output.text() catch {
    error =>
      raise MacosSigningError::Verification(
        detail="failed to decode signing authority: " +
          @debug.render(Repr(error)),
      )
  }
  if !text.contains("Authority=Developer ID Application:") {
    raise MacosSigningError::Verification(
      detail="release signing must use a Developer ID Application identity",
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
) -> Unit {
  let args = macos_codesign_args(
    identity,
    target,
    runtime_options~,
    deep~,
    entitlements~,
  )
  let code = @process.run("codesign", args) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="codesign " + target,
        detail=@debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise MacosSigningError::ToolFailure(
      stage="codesign " + target,
      detail="exit code " + code.to_string(),
    )
  }
}

///|
async fn verify_macos_codesign_target(target : String, deep~ : Bool) -> Unit {
  let args = macos_codesign_verify_args(target, deep~)
  let code = @process.run("codesign", args) catch {
    error =>
      raise MacosSigningError::Verification(
        detail=target + ": " + @debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise MacosSigningError::Verification(
      detail=target + ": exit code " + code.to_string(),
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
async fn resolve_macos_entitlements(
  app : String,
  allow_untrusted_libraries~ : Bool,
) -> String {
  match @sys.get_env_var("PROTON_MACOS_ENTITLEMENTS") {
    Some(path) if path.trim().to_owned() != "" => {
      let path = @path.Path(path.trim().to_owned()).resolve().to_string()
      if @fsutil.path_is_file(path) {
        path
      } else {
        raise MacosSigningError::InvalidConfiguration(
          detail="macOS entitlements file is missing: " + path,
        )
      }
    }
    _ => {
      let path = @fsutil.resolve_path(
        app, "Contents/Resources/proton.entitlements",
      )
      write_text(path, default_macos_entitlements(allow_untrusted_libraries~))
      path
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
async fn notarize_macos_app(plan : PackagePlan, app : String) -> Unit {
  let profile = required_macos_notary_profile()
  let archive = @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".notary.zip",
  )
  remove_tree(archive)
  submit_macos_notarization(app, archive, profile) catch {
    error => {
      remove_tree(archive) catch {
        _ => ()
      }
      raise error
    }
  }
  remove_tree(archive)
}

///|
async fn submit_macos_notarization(
  app : String,
  archive : String,
  profile : String,
) -> Unit {
  let zip_code = @process.run("ditto", [
    "-c", "-k", "--keepParent", app, archive,
  ]) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="create notarization archive",
        detail=@debug.render(Repr(error)),
      )
  }
  guard zip_code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage="create notarization archive",
      detail="exit code " + zip_code.to_string(),
    )
  }
  submit_macos_notarization_artifact(archive, profile)
  staple_macos_artifact(app)
  validate_macos_staple(app)
  assess_macos_app(app)
}

///|
fn required_macos_notary_profile() -> String raise MacosSigningError {
  match @sys.get_env_var("PROTON_NOTARY_PROFILE") {
    Some(profile) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="--notarize requires PROTON_NOTARY_PROFILE",
      )
  }
}

///|
async fn submit_macos_notarization_artifact(
  artifact : String,
  profile : String,
) -> Unit {
  let code = @process.run("xcrun", [
    "notarytool", "submit", artifact, "--keychain-profile", profile, "--wait",
  ]) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="submit notarization",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage="notarytool submit",
      detail="exit code " + code.to_string(),
    )
  }
}

///|
async fn staple_macos_artifact(artifact : String) -> Unit {
  let code = @process.run("xcrun", ["stapler", "staple", artifact]) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="staple notarization ticket",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage="stapler",
      detail="exit code " + code.to_string(),
    )
  }
}

///|
async fn validate_macos_staple(artifact : String) -> Unit {
  let code = @process.run("xcrun", ["stapler", "validate", artifact]) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="validate notarization ticket",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage="stapler validate",
      detail="exit code " + code.to_string(),
    )
  }
}

///|
async fn assess_macos_app(app : String) -> Unit {
  let code = @process.run("spctl", [
    "--assess", "--type", "execute", "--verbose=4", app,
  ]) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage="Gatekeeper assessment",
        detail=@debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise MacosSigningError::ToolFailure(
      stage="Gatekeeper assessment",
      detail="exit code " + code.to_string(),
    )
  }
}

///|
async fn create_zip(source : String, archive : String) -> Unit {
  remove_tree(archive)
  let code = if @path.sep == '\\' {
    @process.run("powershell", [
      "-NoProfile", "-Command", "Compress-Archive", "-Path", source, "-DestinationPath",
      archive,
    ]) catch {
      error =>
        raise PackageToolError::Start(
          tool="Compress-Archive",
          detail=@debug.render(Repr(error)),
        )
    }
  } else {
    @process.run("ditto", [
      "-c", "-k", "--norsrc", "--keepParent", source, archive,
    ]) catch {
      error =>
        raise PackageToolError::Start(
          tool="ditto",
          detail=@debug.render(Repr(error)),
        )
    }
  }
  if code != 0 {
    raise PackageToolError::Exit(tool="zip", code~, detail=archive)
  }
}

///|
async fn resolve_package_config_path(
  cwd : String,
  root : String,
  raw : RawPackageOptions,
) -> String? {
  match raw.config_path {
    Some(path) => Some(@fsutil.resolve_path(cwd, path))
    None => {
      let package_config = @fsutil.resolve_path(
        cwd,
        raw.app_package.unwrap_or(default_package) + "/" + default_config_file,
      )
      let cwd_config = @fsutil.resolve_path(cwd, default_config_file)
      let root_config = @fsutil.resolve_path(root, default_config_file)
      if @fsutil.path_exists(package_config) {
        Some(package_config)
      } else if @fsutil.path_exists(cwd_config) {
        Some(cwd_config)
      } else if @fsutil.path_exists(root_config) {
        Some(root_config)
      } else {
        None
      }
    }
  }
}

///|
async fn find_workspace_root_from(start : String) -> String {
  let mut module_root : String? = None
  for dir = start; dir != ""; {
    if @fsutil.path_exists(@fsutil.path_join(dir, "moon.work")) {
      return dir
    }
    if module_root is None &&
      @fsutil.path_exists(@fsutil.path_join(dir, "moon.mod")) {
      module_root = Some(dir)
    }
    let parent = @fsutil.path_parent(dir)
    if parent == dir {
      return module_root.unwrap_or(start)
    }
    continue parent
  }
  module_root.unwrap_or(start)
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}
