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
  workspace_root : String
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
  macos_icon : String?
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
pub extend PackagePlan with Eq::{not_equal, equal}

///|
pub extend PackagePlan with Debug::{to_repr}

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
  let root = @fsutil.find_project_root_from(cwd)
  let config_path = match resolve_package_config_path(cwd, root, raw) {
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
  let loaded = @proton_config.load_project_config_from_text(
    config_text,
    @fsutil.path_parent(config_path),
    name=config_path,
  ) catch {
    error => raise PackageConfigError::Invalid(path=config_path, error~)
  }
  let project = loaded.config()
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
  let artifacts = execute_package_plan(plan)
  match updater_base_url {
    Some(base_url) =>
      write_updater_metadata(
        plan,
        artifacts,
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
        platform=@cef.current_platform_id(),
      )
    }
  }
  let base_dir = @fsutil.resolve_path(project.base_dir(), ".")
  let backend = project.backend()
  let backend_root = match backend {
    Some(backend) => @fsutil.resolve_path(base_dir, backend.path())
    None => @fsutil.find_project_root_from(base_dir)
  }
  let version = match
    @proton_config.read_moon_mod_metadata(backend_root).version {
    Some(version) if version.trim().to_owned() != "" =>
      version.trim().to_owned()
    _ => raise PackageConfigError::MissingField(field="moon.mod version")
  }
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
  let workspace_root = find_workspace_root_from(base_dir)
  PackagePlan::{
    root: backend_root,
    workspace_root,
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
    macos_icon: first_macos_icon(package_config.icons()),
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
async fn execute_package_plan(plan : PackagePlan) -> Array[String] {
  // Resolve the active runtime before any build work so a missing
  // `proton_cli cef setup` fails fast instead of after a full application build.
  let runtime = read_active_runtime(plan.workspace_root)
  let executable = run_package_build(plan)
  if !@fsutil.path_exists(executable) || !@fsutil.path_is_file(executable) {
    raise PackagePlanError::MissingExecutable(path=executable)
  }
  let helper = @build.build_cef_process(plan.root)
  let spec = package_spec(plan, executable, helper, runtime)
  let artifacts = @packager.build_with(spec, package_customization(plan), async fn(
    layout,
  ) {
    prepare_proton_package(plan, helper, layout)
  })
  for artifact in artifacts {
    println("Packaged: " + artifact)
  }
  artifacts
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
async fn read_active_runtime(root : String) -> String {
  match @env.get_env_var("PROTON_NATIVE_DIST") {
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
      guard fields is { "platform": String(platform), .. } else {
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
      match fields {
        { "dist": String(dist), .. } =>
          require_runtime(@fsutil.resolve_path(root, dist))
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
async fn require_runtime(path : String) -> String {
  if @fsutil.path_is_dir(path) {
    path
  } else {
    raise DirectoryMissing(path~)
  }
}

///|
/// Mach-O `filetype` values this packager can name. Only `MH_EXECUTE` is
/// spawnable; `MH_DSYM` is the one that actually shows up here, because a
/// debug build mirrors the executable's basename inside
/// `<name>.dSYM/Contents/Resources/DWARF/`.
const MachoExecute : Int = 0x2

///|
fn macho_filetype_name(filetype : Int) -> String {
  match filetype {
    0x1 => "MH_OBJECT"
    0x2 => "MH_EXECUTE"
    0x6 => "MH_DYLIB"
    0x8 => "MH_BUNDLE"
    0xa => "MH_DSYM"
    _ => "0x" + filetype.to_string()
  }
}

///|
fn macho_u32_le(data : Bytes, offset : Int) -> Int {
  data[offset].to_int() |
  (data[offset + 1].to_int() << 8) |
  (data[offset + 2].to_int() << 16) |
  (data[offset + 3].to_int() << 24)
}

///|
/// The `filetype` of a thin little-endian Mach-O, or `None` for anything this
/// reader will not judge.
///
/// 64- and 32-bit thin headers agree up to `filetype`, so one offset serves
/// both. Universal binaries (`FAT_MAGIC`) and non-Mach-O files return `None`
/// on purpose: the caller rejects only what it can prove wrong, so a format
/// this function does not understand is never turned into a build failure.
/// Extending to fat archives means walking the arch table and judging each
/// contained header.
fn macho_thin_filetype(data : Bytes) -> Int? {
  guard data.length() >= 16 else { return None }
  let magic = macho_u32_le(data, 0)
  guard magic == 0xfeedfacf || magic == 0xfeedface else { return None }
  Some(macho_u32_le(data, 12))
}

///|
/// Refuse to ship a bundle executable the kernel will not spawn.
///
/// `codesign` cannot stand in for this: a dSYM companion is a legitimate
/// Mach-O and signs and verifies exactly like the real binary, differing
/// only in the header's `filetype`. Nor can the executable bit, which this
/// packager sets on whatever it staged. So a bundle carrying symbols where
/// its binary belongs passes every other check and then fails at launch with
/// `Launchd job spawn failed` — this is the only place that catches it.
async fn require_launchable_macho(path : String) -> Unit {
  let data = @async_fs.read_file(path) catch {
    error =>
      raise PackageFileSystemError::Read(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard macho_thin_filetype(data.binary()) is Some(filetype) else { return }
  guard filetype != MachoExecute else { return }
  raise PackagePlanError::NotLaunchableMachO(path~, filetype~)
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
fn relative_to_base(base : String, path : String) -> String? {
  let root = @fsutil.resolve_path(base, ".")
  let candidate = @fsutil.resolve_path(base, path)
  guard @fsutil.path_is_within(root, candidate) else { return None }
  let relative = normalize_slashes(@fsutil.relative_path(root, candidate))
  if relative == "" {
    Some(".")
  } else if relative == ".." || relative.has_prefix("../") {
    None
  } else {
    Some(relative)
  }
}

///|
fn normalize_slashes(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn path_basename(path : String) -> String {
  let native_path : @path.Path = path
  native_path.basename().to_owned()
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
async fn write_text(
  path : String,
  text : String,
) -> Unit raise PackageFileSystemError {
  @async_fs.write_file(path, text, create_mode=CreateOrTruncate) catch {
    error => raise Write(path~, detail=@debug.render(Repr(error)))
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
  let manifest : Json = {
    "schema_version": 1,
    "kind": kind,
    "product_name": plan.product_name,
    "identifier": plan.identifier,
    "version": plan.version,
    "bundle_version": plan.bundle_version,
    "targets": plan.targets,
    "url_schemes": plan.url_schemes,
    "document_types": plan.document_types.map(fn(document_type) -> Json {
      {
        "name": document_type.name,
        "extensions": document_type.extensions,
        "role": document_type.role,
      }
    }),
  }
  write_text(
    @fsutil.resolve_path(destination, "proton-package.json"),
    manifest.stringify() + "\n",
  )
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
