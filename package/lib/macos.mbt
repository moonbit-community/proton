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
  executable : String,
  short_version : String,
  bundle_version : String,
) -> String {
  let schemes = StringBuilder::new()
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
  let document_entries = StringBuilder::new()
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
    #|{{ICON}}{{URL_TYPES}}{{DOCUMENT_TYPES}}
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
}

///|
fn macos_versions(value : String) -> (String, String) raise PackagePlanError {
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
    Some(value) if value.trim().to_owned() != "" => value.trim().to_owned()
    _ => short_version
  }
  (short_version, bundle_version)
}

///|
fn macos_signing_identity(spec : PackageSpec) -> String raise MacosSigningError {
  if !spec.sign {
    return "-"
  }
  match @env.get_env_var("PROTON_MACOS_SIGNING_IDENTITY") {
    Some(identity) if identity.trim().to_owned() != "" =>
      identity.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="signing requires PROTON_MACOS_SIGNING_IDENTITY",
      )
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
async fn sign_macos_app(spec : PackageSpec, app : String) -> Unit {
  let identity = macos_signing_identity(spec)
  let args = ["--force", "--deep", "--sign", identity]
  if identity != "-" {
    args.push("--timestamp")
    args.push("--options")
    args.push("runtime")
  }
  args.push(app)
  run_macos_tool("/usr/bin/codesign", args, "sign application")
  run_macos_tool(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", app],
    "verify application signature",
  )
}

///|
async fn create_macos_zip(app : String, destination : String) -> Unit {
  let staging = destination + ".staging"
  remove_tree(staging)
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
  let profile = match @env.get_env_var("PROTON_MACOS_NOTARY_PROFILE") {
    Some(profile) if profile.trim().to_owned() != "" =>
      profile.trim().to_owned()
    _ =>
      raise MacosSigningError::InvalidConfiguration(
        detail="notarization requires PROTON_MACOS_NOTARY_PROFILE",
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
  if artifact.has_suffix(".dmg") {
    run_macos_tool(
      "/usr/bin/xcrun",
      ["stapler", "staple", artifact],
      "staple DMG",
    )
  }
}

///|
async fn package_macos(spec : PackageSpec) -> Array[String] {
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
  let (short_version, bundle_version) = macos_versions(spec.version)
  write_text(
    path_join(contents, "Info.plist"),
    macos_info_plist(spec, name, short_version, bundle_version),
  )
  sign_macos_app(spec, app)
  let outputs : Array[String] = []
  let zip = macos_zip_path(spec)
  let dmg = macos_dmg_path(spec)
  if spec.formats.contains(Zip) ||
    (spec.notarize && !spec.formats.contains(Dmg)) {
    create_macos_zip(app, zip)
    if spec.formats.contains(Zip) {
      outputs.push(zip)
    }
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
    if !spec.formats.contains(Zip) && !spec.formats.contains(Dmg) {
      remove_tree(zip)
    }
  }
  if spec.formats.contains(App) {
    let destination = macos_app_path(spec)
    promote(app, destination)
    outputs.push(destination)
  }
  remove_tree(staging_root)
  outputs
}
