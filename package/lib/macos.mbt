///|
fn macos_staging_root(spec : PackageSpec) -> String {
  path_join(spec.output, "." + executable_name(spec.product_name) + ".staging")
}

///|
fn macos_app_path(spec : PackageSpec) -> String {
  path_join(spec.output, spec.product_name + ".app")
}

///|
fn macos_zip_path(spec : PackageSpec) -> String {
  path_join(spec.output, spec.product_name + ".app.zip")
}

///|
fn macos_dmg_path(spec : PackageSpec) -> String {
  path_join(spec.output, spec.product_name + ".dmg")
}

///|
fn macos_info_plist(
  spec : PackageSpec,
  customization : PackageCustomization,
  executable : String,
  short_version : String,
  bundle_version : String,
) -> String {
  let custom_properties = StringBuilder()
  for property in customization.macos_plist_strings {
    custom_properties <+
      $|<key>\{xml_escape(property.key)}</key><string>\{xml_escape(property.value)}</string>
  }
  let schemes = StringBuilder()
  for scheme in spec.url_schemes {
    schemes <+
      $|<string>\{xml_escape(scheme)}</string>
  }
  let url_types = if schemes.to_string() == "" {
    ""
  } else {
    "<key>CFBundleURLTypes</key><array><dict>" +
    "<key>CFBundleURLName</key><string>" +
    xml_escape(spec.identifier) +
    "</string><key>CFBundleURLSchemes</key><array>" +
    schemes.to_string() +
    "</array></dict></array>"
  }
  let document_entries = StringBuilder()
  for document_type in spec.document_types {
    document_entries <+
      $|<dict><key>CFBundleTypeName</key><string>\{xml_escape(document_type.name)}</string><key>CFBundleTypeRole</key><string>\{xml_escape(document_type.role)}</string><key>CFBundleTypeExtensions</key><array>
    for extension in document_type.extensions {
      document_entries <+
        $|<string>\{xml_escape(extension)}</string>
    }
    document_entries <+
      "</array><key>LSHandlerRank</key><string>Owner</string></dict>"
  }
  let document_types = if document_entries.to_string() == "" {
    ""
  } else {
    "<key>CFBundleDocumentTypes</key><array>" +
    document_entries.to_string() +
    "</array>"
  }
  let icon = match first_icon(spec, ".icns") {
    Some(_) => "<key>CFBundleIconFile</key><string>AppIcon</string>"
    None => ""
  }
  let template =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0"><dict>
    #|<key>CFBundleDisplayName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundleExecutable</key><string>{{EXECUTABLE}}</string>
    #|<key>CFBundleIdentifier</key><string>{{IDENTIFIER}}</string>
    #|<key>CFBundleName</key><string>{{PRODUCT}}</string>
    #|<key>CFBundlePackageType</key><string>APPL</string>
    #|<key>CFBundleShortVersionString</key><string>{{SHORT_VERSION}}</string>
    #|<key>CFBundleVersion</key><string>{{BUNDLE_VERSION}}</string>
    #|<key>LSMinimumSystemVersion</key><string>12.0</string>
    #|<key>NSHighResolutionCapable</key><true/>
    #|{{ICON}}{{URL_TYPES}}{{DOCUMENT_TYPES}}{{CUSTOM_PROPERTIES}}
    #|</dict></plist>
    #|
  template
  .replace_all(old="{{PRODUCT}}", new=xml_escape(spec.product_name))
  .replace_all(old="{{EXECUTABLE}}", new=xml_escape(executable))
  .replace_all(old="{{IDENTIFIER}}", new=xml_escape(spec.identifier))
  .replace_all(old="{{SHORT_VERSION}}", new=xml_escape(short_version))
  .replace_all(old="{{BUNDLE_VERSION}}", new=xml_escape(bundle_version))
  .replace_all(old="{{ICON}}", new=icon)
  .replace_all(old="{{URL_TYPES}}", new=url_types)
  .replace_all(old="{{DOCUMENT_TYPES}}", new=document_types)
  .replace_all(old="{{CUSTOM_PROPERTIES}}", new=custom_properties.to_string())
}

///|
/// Resolves the macOS short and bundle versions from a package version.
///
/// `PROTON_MACOS_BUILD_NUMBER`, when present, overrides the bundle version.
pub fn macos_versions(
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
    Some(value) if value.trim().to_owned() != "" =>
      validate_macos_bundle_version(value.trim().to_owned())
    _ => short_version
  }
  (short_version, bundle_version)
}

///|
fn validate_macos_bundle_version(
  value : String,
) -> String raise PackagePlanError {
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
fn macos_signing_identity(spec : PackageSpec) -> String raise MacosSigningError {
  if !spec.sign {
    return "-"
  }
  let identity = match @env.get_env_var("PROTON_MACOS_SIGNING_IDENTITY") {
    Some(identity) if identity.trim().to_owned() != "" =>
      identity.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="signing requires PROTON_MACOS_SIGNING_IDENTITY",
      )
  }
  if identity == "-" {
    guard macos_adhoc_signing_allowed() else {
      raise MacosSigningError::InvalidConfiguration(
        detail="ad-hoc signing is not a release path; set PROTON_MACOS_ALLOW_ADHOC=1 only for local diagnostics",
      )
    }
    guard !spec.notarize else {
      raise MacosSigningError::InvalidConfiguration(
        detail="notarization requires a Developer ID Application identity",
      )
    }
  }
  identity
}

///|
fn macos_adhoc_signing_allowed() -> Bool {
  match @env.get_env_var("PROTON_MACOS_ALLOW_ADHOC") {
    Some(value) =>
      match value.trim().to_owned().to_lower() {
        "1" | "true" | "yes" | "on" => true
        _ => false
      }
    None => false
  }
}

///|
async fn run_macos_tool(
  tool : String,
  args : Array[String],
  stage : String,
) -> Unit {
  let (code, output) = @process.collect_output_merged(tool, args) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage~,
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
}

///|
async fn sign_macos_app(
  spec : PackageSpec,
  customization : PackageCustomization,
  layout : PackageLayout,
) -> Unit {
  let identity = macos_signing_identity(spec)
  let entitlements = resolve_macos_entitlements(
    layout.resources,
    allow_untrusted_libraries=identity == "-",
  )
  for target in customization.macos_sign_targets {
    let path = path_join(layout.root, target.path)
    guard path_exists(path) else {
      raise MacosSigningError::Verification(
        detail="required signing target is missing: " + path,
      )
    }
    codesign_macos_target(
      identity,
      path,
      runtime_options=target.runtime_options,
      entitlements=if target.entitlements { Some(entitlements) } else { None },
      identifier=target.identifier,
    )
  }
  codesign_macos_target(
    identity,
    layout.executable,
    runtime_options=true,
    entitlements=Some(entitlements),
    identifier=None,
  )
  codesign_macos_target(
    identity,
    layout.root,
    runtime_options=true,
    entitlements=Some(entitlements),
    identifier=None,
  )
  run_macos_tool(
    "/usr/bin/codesign",
    macos_codesign_verify_args(layout.root, deep=true),
    "verify application signature",
  )
  if spec.sign && identity != "-" {
    verify_macos_developer_id(layout.root)
  }
}

///|
async fn codesign_macos_target(
  identity : String,
  target : String,
  runtime_options~ : Bool,
  entitlements~ : String?,
  identifier~ : String?,
) -> Unit {
  let args = macos_codesign_args(
    identity,
    target,
    runtime_options~,
    entitlements~,
    identifier~,
  )
  run_macos_tool("/usr/bin/codesign", args, "sign " + target)
}

///|
fn macos_codesign_args(
  identity : String,
  target : String,
  runtime_options~ : Bool,
  entitlements~ : String?,
  identifier~ : String?,
) -> Array[String] {
  let args = ["--force"]
  if identity != "-" {
    args.push("--timestamp")
  }
  if runtime_options {
    args.append(["--options", "runtime"])
  }
  match entitlements {
    Some(path) if runtime_options => args.append(["--entitlements", path])
    _ => ()
  }
  match identifier {
    Some(value) => args.append(["-i", value])
    None => ()
  }
  args.append(["--sign", identity, target])
  args
}

///|
fn macos_codesign_verify_args(target : String, deep~ : Bool) -> Array[String] {
  let args = ["--verify"]
  if deep {
    args.push("--deep")
  }
  args.append(["--strict", "--verbose=2", target])
  args
}

///|
async fn verify_macos_developer_id(app : String) -> Unit {
  let (code, output) = @process.collect_output_merged("/usr/bin/codesign", [
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
  guard text.contains("Authority=Developer ID Application:") else {
    raise MacosSigningError::Verification(
      detail="release signing must use a Developer ID Application identity",
    )
  }
}

///|
async fn resolve_macos_entitlements(
  resources : String,
  allow_untrusted_libraries~ : Bool,
) -> String {
  match @env.get_env_var("PROTON_MACOS_ENTITLEMENTS") {
    Some(path) if path.trim().length() > 0 => {
      let path = @path.Path(path.trim().to_owned()).resolve().to_string()
      guard path_is_file(path) else {
        raise MacosSigningError::InvalidConfiguration(
          detail="macOS entitlements file is missing: " + path,
        )
      }
      path
    }
    _ => {
      let path = path_join(resources, "proton.entitlements")
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
async fn create_macos_zip(app : String, destination : String) -> Unit {
  let staging = destination + ".staging"
  remove_tree(staging)
  errdefer (remove_tree(staging) catch { _ => () })
  run_macos_tool(
    "/usr/bin/ditto",
    ["-c", "-k", "--sequesterRsrc", "--keepParent", app, staging],
    "create application zip",
  )
  promote(staging, destination)
}

///|
async fn create_macos_dmg(
  spec : PackageSpec,
  app : String,
  destination : String,
) -> Unit {
  let root = path_join(macos_staging_root(spec), "dmg-root")
  // hdiutil chooses its output format from the final extension.
  let staging = destination + ".staging.dmg"
  remove_tree(root)
  remove_tree(staging)
  ensure_dir(root)
  errdefer {
    remove_tree(root) catch {
      _ => ()
    }
    remove_tree(staging) catch {
      _ => ()
    }
  }
  copy_tree(app, path_join(root, spec.product_name + ".app"))
  @async_fs.symlink(target="/Applications", path_join(root, "Applications")) catch {
    error =>
      raise PackageFileSystemError::Write(
        path=root,
        detail=@debug.render(Repr(error)),
      )
  }
  run_macos_tool(
    "/usr/bin/hdiutil",
    [
      "create",
      "-volname",
      spec.product_name,
      "-srcfolder",
      root,
      "-format",
      "UDZO",
      "-ov",
      staging,
    ],
    "create DMG",
  )
  if spec.sign {
    run_macos_tool(
      "/usr/bin/codesign",
      [
        "--force",
        "--timestamp",
        "--sign",
        macos_signing_identity(spec),
        staging,
      ],
      "sign DMG",
    )
    run_macos_tool(
      "/usr/bin/codesign",
      ["--verify", "--strict", staging],
      "verify DMG signature",
    )
  }
  run_macos_tool("/usr/bin/hdiutil", ["verify", staging], "verify DMG")
  promote(staging, destination)
  remove_tree(root)
}

///|
async fn notarize_macos(
  spec : PackageSpec,
  app : String,
  artifact : String,
) -> Unit {
  guard spec.notarize else { return }
  let profile = match
    (
      @env.get_env_var("PROTON_MACOS_NOTARY_PROFILE"),
      @env.get_env_var("PROTON_NOTARY_PROFILE"),
    ) {
    (Some(profile), _) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    (_, Some(profile)) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="notarization requires PROTON_MACOS_NOTARY_PROFILE or PROTON_NOTARY_PROFILE",
      )
  }
  run_macos_tool(
    "/usr/bin/xcrun",
    ["notarytool", "submit", artifact, "--keychain-profile", profile, "--wait"],
    "submit notarization",
  )
  run_macos_tool(
    "/usr/bin/xcrun",
    ["stapler", "staple", app],
    "staple application",
  )
  run_macos_tool(
    "/usr/bin/xcrun",
    ["stapler", "validate", app],
    "validate application ticket",
  )
  if artifact.has_suffix(".dmg") {
    run_macos_tool(
      "/usr/bin/xcrun",
      ["stapler", "staple", artifact],
      "staple DMG",
    )
    run_macos_tool(
      "/usr/bin/xcrun",
      ["stapler", "validate", artifact],
      "validate DMG ticket",
    )
  }
  run_macos_tool(
    "/usr/sbin/spctl",
    ["--assess", "--type", "execute", "--verbose=4", app],
    "assess notarized application",
  )
}

///|
async fn package_macos(
  spec : PackageSpec,
  customization : PackageCustomization,
  prepare : async (PackageLayout) -> Unit,
) -> Array[String] {
  guard path_is_file(spec.executable) else {
    raise PackagePlanError::MissingExecutable(path=spec.executable)
  }
  let staging_root = macos_staging_root(spec)
  let app = path_join(staging_root, spec.product_name + ".app")
  let contents = path_join(app, "Contents")
  let macos = path_join(contents, "MacOS")
  let resources = path_join(contents, "Resources")
  let frameworks = path_join(contents, "Frameworks")
  remove_tree(staging_root)
  errdefer (remove_tree(staging_root) catch { _ => () })
  for directory in [macos, resources, frameworks] {
    ensure_dir(directory)
  }
  let name = executable_name(spec.product_name)
  let staged_executable = path_join(macos, name)
  copy_file(spec.executable, staged_executable)
  @async_fs.chmod(staged_executable, 0o755)
  copy_payloads(spec, resources, frameworks, macos)
  match first_icon(spec, ".icns") {
    Some(icon) => copy_file(icon, path_join(resources, "AppIcon.icns"))
    None => ()
  }
  let layout = PackageLayout::{
    root: app,
    executable: staged_executable,
    resources,
    libraries: frameworks,
    executables: macos,
  }
  prepare(layout)
  let (short_version, bundle_version) = macos_versions(spec.version)
  write_text(
    path_join(contents, "Info.plist"),
    macos_info_plist(spec, customization, name, short_version, bundle_version),
  )
  sign_macos_app(spec, customization, layout)
  let outputs : Array[String] = []
  let zip = macos_zip_path(spec)
  let dmg = macos_dmg_path(spec)
  if spec.notarize && !spec.formats.contains(Dmg) {
    create_macos_zip(app, zip)
  }
  if spec.formats.contains(Dmg) {
    create_macos_dmg(spec, app, dmg)
    outputs.push(dmg)
  }
  if spec.notarize {
    notarize_macos(
      spec,
      app,
      if spec.formats.contains(Dmg) {
        dmg
      } else {
        zip
      },
    )
  }
  if spec.formats.contains(Zip) {
    // Recreate after notarization so the archive contains the stapled app.
    create_macos_zip(app, zip)
    outputs.push(zip)
  } else if spec.notarize && !spec.formats.contains(Dmg) {
    remove_tree(zip)
  }
  if spec.formats.contains(App) {
    let destination = macos_app_path(spec)
    promote(app, destination)
    outputs.push(destination)
  }
  remove_tree(staging_root)
  outputs
}
