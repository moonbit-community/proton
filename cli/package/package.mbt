///|
let default_package = "app"

///|
let default_config_file = "proton.project.json"

///|
struct RawPackageOptions {
  app_package : String?
  config_path : String?
  targets : Array[String]
  output : String?
  release : Bool
  dry_run : Bool
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
pub extend RawPackageOptions with Eq::{not_equal, equal}

///|
pub extend RawPackageOptions with Debug::{to_repr}

///|
struct PackagePlan {
  root : String
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
  release : Bool
  base_dir : String
  frontend_dist : String?
  resources : Array[String]
  sign_binaries : Array[String]
  icons : Array[String]
  url_schemes : Array[String]
  document_types : Array[@proton_config.ProjectDocumentType]
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
pub extend PackagePlan with Eq::{not_equal, equal}

///|
pub extend PackagePlan with Debug::{to_repr}

///|
/// Returns the declarative `proton_cli package` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "package",
    about="Package a Proton application",
    flags=[
      FlagArg("release", about="Build and package the release output"),
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
        about="Package target (app, zip, Windows nsis, macOS dmg, or Linux appimage); may be repeated",
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
  let config_path = match resolve_package_config_path(cwd, raw) {
    Some(path) => path
    None => raise PackageConfigError::NotFound(path="proton.project.json")
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
  let project = @proton_config.load_project_config_from_text(
    config_text,
    @fsutil.path_parent(config_path),
    name=config_path,
  ) catch {
    error => raise PackageConfigError::Invalid(path=config_path, error~)
  }
  let updater_base_url = match matches.values {
    { "updater-base-url": [base_url, ..], .. } => Some(base_url)
    _ => None
  }
  let update_revision = updater_revision_from_matches(matches, updater_base_url)
  let plan = build_package_plan(raw, config_path, project, update_revision)
  print_package_plan(plan, raw.dry_run)
  if raw.dry_run {
    return
  }
  let result = execute_package_plan(plan)
  match updater_base_url {
    Some(base_url) =>
      write_updater_metadata(
        plan,
        result.artifacts(),
        result.platform(),
        base_url,
        match matches.values {
          { "updater-published-at": [published_at, ..], .. } => published_at
          _ => raise MissingPublishedAt
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
  match matches.values {
    { "updater-revision": [value, ..], .. } => {
      let revision = @string.parse_uint64(value[:]) catch {
        _ => raise InvalidRevision(value~)
      }
      guard revision > 0UL else { raise InvalidRevision(value~) }
      revision
    }
    _ => {
      guard base_url is None else { raise MissingRevision }
      0UL
    }
  }
}

///|
fn package_options_from_matches(
  matches : @argparse.Matches,
) -> RawPackageOptions raise PackageUsageError {
  guard matches.values
    is {
      "target"? : Some(targets)
      | (None with targets = []),
      "package"? : Some(app_package)
      | (None with app_package = []),
      "config"? : Some(config_path)
      | (None with config_path = []),
      "output"? : Some(output)
      | (None with output = []),
      ..
    }
  guard matches.flags
    is {
      "notarize"? : Some(notarize)
      | (None with notarize = false),
      "release"? : Some(release)
      | (None with release = false),
      "dry-run"? : Some(dry_run)
      | (None with dry_run = false),
      "sign"? : Some(sign)
      | (None with sign = false),
      ..
    }
  for target in targets {
    validate_package_target(target)
  }
  RawPackageOptions::{
    app_package: app_package.get(0),
    config_path: config_path.get(0),
    targets,
    output: output.get(0),
    release,
    dry_run,
    sign: sign || notarize,
    notarize,
  }
}

///|
/// The platform `package` is running on.
///
/// Packaging drives the host's own tooling -- codesign, makensis,
/// appimagetool -- so the host decides both which targets can be built and
/// which artifact an update downloads.
pub(all) enum PackageHost {
  Macos
  Windows
  Linux
} derive(Eq)

///|
pub extend PackageHost with Eq::{not_equal, equal}

///|
/// The host `package` is running on, which is the platform it can build for.
async fn current_package_host() -> PackageHost {
  if @path.sep == '\\' {
    Windows
  } else if is_macos_host() {
    Macos
  } else {
    Linux
  }
}

///|
fn package_host_name(host : PackageHost) -> String {
  match host {
    Macos => "macOS"
    Windows => "Windows"
    Linux => "Linux"
  }
}

///|
/// The host a platform id names. Used where the question is which platform's
/// artifacts are being described rather than which one is running -- update
/// metadata names the platform it was built for, and has the id in hand.
fn package_host_of(platform : String) -> PackageHost? {
  if platform.has_prefix("darwin-") {
    Some(Macos)
  } else if platform.has_prefix("win32-") {
    Some(Windows)
  } else if platform.has_prefix("linux-") {
    Some(Linux)
  } else {
    None
  }
}

///|
/// Every target `package` accepts, and the hosts that can build it.
///
/// A target only builds on the platform it targets, because producing it runs
/// that platform's own tooling. Absent from this table means not a target at
/// all, so one table answers both "is this a target?" and "can this host build
/// it?" -- previously separate checks that could disagree.
fn package_target_hosts(target : String) -> Array[PackageHost]? {
  match target {
    // `app` names a macOS bundle and a Windows portable directory; on Linux
    // the distributable unit is the AppImage itself.
    "app" => Some([Macos, Windows])
    "zip" => Some([Macos, Windows])
    "dmg" => Some([Macos])
    "nsis" => Some([Windows])
    "appimage" => Some([Linux])
    _ => None
  }
}

///|
fn validate_package_target(target : String) -> Unit raise PackageUsageError {
  guard package_target_hosts(target) is Some(_) else {
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
  let package_config = match project.package_config() {
    Some(package_config) => package_config
    None => raise PackageConfigError::PackageMissing
  }
  let product_name = validate_product_name(package_config.product_name)
  let identifier = package_config.identifier
  let identifier = validate_bundle_identifier(identifier)
  let host = current_package_host()
  let targets = if raw.targets.length() > 0 {
    copy_strings(raw.targets)
  } else if package_config.formats.length() > 0 {
    copy_strings(package_config.formats)
  } else {
    match host {
      Linux => ["appimage"]
      Macos | Windows => ["app", "zip"]
    }
  }
  for target in targets {
    guard package_target_hosts(target) is Some(hosts) && hosts.contains(host) else {
      raise PackagePlanError::UnsupportedTargetForPlatform(
        target~,
        platform=package_host_name(host),
      )
    }
  }
  let base_dir = @fsutil.resolve_path(project.base_dir(), ".")
  let backend = project.backend()
  let backend_root = match backend {
    Some(backend) => @fsutil.resolve_path(base_dir, backend.path())
    None => base_dir
  }
  let version = @packager.validate_package_version(package_config.version)
  let (macos_version, bundle_version) = if is_macos_host() {
    validate_macos_version(version)
  } else {
    (version, version)
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
    None => @fsutil.resolve_path(base_dir, package_config.output())
  }
  let frontend_dist = match project.frontend() {
    Some(frontend) => frontend.dist()
    None => None
  }
  PackagePlan::{
    root: backend_root,
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
    release: raw.release,
    base_dir,
    frontend_dist,
    resources: package_config.resources(),
    sign_binaries: match package_config.sign() {
      Some(sign) => sign.binaries()
      None => []
    },
    icons: package_config.icons(),
    url_schemes: package_config.url_schemes(),
    document_types: package_config.document_types(),
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
  let bundle_version = match @env.get_env_var("PROTON_MACOS_BUILD_NUMBER") {
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
  let sign_binaries = if plan.sign_binaries.length() == 0 {
    "none"
  } else {
    plan.sign_binaries.join(", ")
  }
  println("  sign binaries: " + sign_binaries)
  let build_mode = if plan.release { "release" } else { "debug" }
  println("  build mode: " + build_mode)
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
async fn execute_package_plan(plan : PackagePlan) -> @bundle.BundleResult {
  let executable = run_package_build(plan)
  if !@fsutil.path_exists(executable) || !@fsutil.path_is_file(executable) {
    raise PackagePlanError::MissingExecutable(path=executable)
  }
  let helper = @cef_store.resolve_default_helper()
  let document_types = plan.document_types.map(document_type => {
    @packager.DocumentType::new(
      document_type.name,
      document_type.extensions.copy(),
      role=document_type.role,
    )
  })
  let formats = plan.targets.map(target => {
    @packager.PackageFormat::parse(target)
  })
  let package_spec = @packager.PackageSpec::new(
    executable,
    plan.product_name,
    plan.identifier,
    plan.version,
    formats,
    plan.output,
    icons=plan.icons,
    url_schemes=plan.url_schemes,
    document_types~,
    sign=plan.sign,
    notarize=plan.notarize,
  )
  let spec = @bundle.ProtonBundleSpec::new(
    package_spec,
    helper,
    plan.base_dir,
    plan.macos_version,
    plan.bundle_version,
    plan.frontend_dist,
    update_revision=plan.update_revision,
    resources=plan.resources,
    sign_binaries=plan.sign_binaries,
  )
  let result = @bundle.build(spec)
  let artifacts = result.artifacts()
  for artifact in artifacts {
    println("Packaged: " + artifact)
  }
  result
}

///|
async fn is_macos_host() -> Bool {
  @fsutil.path_exists("/System/Library/CoreServices/SystemVersion.plist")
}

///|
async fn run_package_build(plan : PackagePlan) -> String {
  @build.build_executable(
    plan.root,
    plan.app_package,
    plan.config_path,
    plan.release,
  )
}

///|
async fn resolve_package_config_path(
  cwd : String,
  raw : RawPackageOptions,
) -> String? {
  match raw.config_path {
    Some(path) => Some(@fsutil.resolve_path(cwd, path))
    None => {
      let cwd_config = @fsutil.resolve_path(cwd, default_config_file)
      if @fsutil.path_exists(cwd_config) {
        Some(cwd_config)
      } else {
        None
      }
    }
  }
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}
