///|
let default_package = "app"

///|
let default_config_file = "proton.project.json"

///|
struct RawPackageOptions {
  app_package : String?
  config_path : String?
  package_args : @package_args.PackageArguments
  release : Bool
  dry_run : Bool
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
  update_revision : UInt64
  formats : Array[@packager.PackageFormat]
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
  let flags = @package_args.flags()
  flags.push(
    @argparse.FlagArg("release", about="Build and package the release output"),
  )
  flags.push(
    @argparse.FlagArg("dry-run", about="Print the resolved package plan"),
  )
  let options = [
    @argparse.OptionArg("package", about="MoonBit application package"),
    @argparse.OptionArg("config", about="Proton project config"),
  ]
  options.append(@package_args.options())
  options.append([
    @argparse.OptionArg(
      "updater-base-url",
      about="Emit update metadata with artifacts served from this https base URL",
    ),
    @argparse.OptionArg(
      "updater-published-at",
      about="Publication instant for the manifest fragment (YYYY-MM-DDTHH:MM:SSZ)",
    ),
    @argparse.OptionArg(
      "updater-revision",
      allow_hyphen_values=true,
      about="Monotonic release sequence embedded in the app and signed manifest",
    ),
  ])
  @argparse.Command(
    "package",
    about="Package a Proton application",
    flags~,
    options~,
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
) -> RawPackageOptions raise @packager.PackagePlanError {
  guard matches.values
    is {
      "package"? : Some(app_package)
      | (None with app_package = []),
      "config"? : Some(config_path)
      | (None with config_path = []),
      ..
    }
  guard matches.flags
    is {
      "release"? : Some(release)
      | (None with release = false),
      "dry-run"? : Some(dry_run)
      | (None with dry_run = false),
      ..
    }
  RawPackageOptions::{
    app_package: app_package.get(0),
    config_path: config_path.get(0),
    package_args: @package_args.from_matches(matches),
    release,
    dry_run,
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
  let product_name = @packager.validate_product_name(
    raw.package_args.product_name.unwrap_or(package_config.product_name),
  )
  let identifier = @packager.validate_identifier(
    raw.package_args.identifier.unwrap_or(package_config.identifier),
  )
  let configured_formats = if raw.package_args.formats.length() > 0 {
    raw.package_args.formats.copy()
  } else if package_config.formats.length() > 0 {
    package_config.formats.map(value => @packager.PackageFormat::parse(value))
  } else {
    []
  }
  let formats = @packager.resolve_package_formats(configured_formats)
  let base_dir = @fsutil.resolve_path(project.base_dir(), ".")
  let backend = project.backend()
  let backend_root = match backend {
    Some(backend) => @fsutil.resolve_path(base_dir, backend.path())
    None => base_dir
  }
  let version = @packager.validate_package_version(
    raw.package_args.version.unwrap_or(package_config.version),
  )
  let app_package = match raw.app_package {
    Some(app_package) => app_package
    None =>
      match backend {
        Some(backend) => backend.app_package()
        None => default_package
      }
  }
  let output = match raw.package_args.output {
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
    update_revision,
    formats,
    output,
    release: raw.release,
    base_dir,
    frontend_dist,
    resources: package_config.resources(),
    sign_binaries: match package_config.sign() {
      Some(sign) => sign.binaries()
      None => []
    },
    icons: if raw.package_args.icons.length() > 0 {
      raw.package_args.icons.map(icon => @fsutil.resolve_path(base_dir, icon))
    } else {
      package_config.icons()
    },
    url_schemes: if raw.package_args.url_schemes.length() > 0 {
      raw.package_args.url_schemes.copy()
    } else {
      package_config.url_schemes()
    },
    document_types: package_config.document_types(),
    sign: raw.package_args.sign,
    notarize: raw.package_args.notarize,
  }
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
  println(
    "  formats: " + plan.formats.map(format => format.to_string()).join(", "),
  )
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
    raise @packager.PackagePlanError::MissingExecutable(path=executable)
  }
  let helper = @cef_store.resolve_default_helper()
  let document_types = plan.document_types.map(document_type => {
    @packager.DocumentType(
      document_type.name,
      document_type.extensions.copy(),
      role=document_type.role,
    )
  })
  let package_spec = @packager.PackageSpec(
    executable,
    plan.product_name,
    plan.identifier,
    plan.version,
    plan.formats,
    plan.output,
    icons=plan.icons,
    url_schemes=plan.url_schemes,
    document_types~,
    sign=plan.sign,
    notarize=plan.notarize,
  )
  let spec = @bundle.ProtonBundleSpec(
    package_spec,
    helper,
    plan.base_dir,
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
