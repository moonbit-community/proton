///|
fn host_path(value : String) -> @path.Path {
  if @path.sep == '\\' {
    value.replace_all(old="/", new="\\")
  } else {
    value
  }
}

///|
fn resolve_path(base : String, value : String) -> String {
  let path = host_path(value)
  if path.is_absolute() {
    path.resolve().to_string()
  } else {
    host_path(base).join(path).resolve().to_string()
  }
}

///|
fn path_parent(value : String) -> String {
  host_path(value).dirname().to_string()
}

///|
fn relative_path(base : String, value : String) -> String {
  host_path(value)
  .resolve()
  .relative(base=host_path(base).resolve())
  .to_string()
}

///|
async fn path_exists(value : String) -> Bool {
  @async_fs.exists(value)
}

///|
async fn path_is_file(value : String) -> Bool {
  if !path_exists(value) {
    return false
  }
  @async_fs.kind(value) is Regular
}

///|
async fn path_is_dir(value : String) -> Bool {
  if !path_exists(value) {
    return false
  }
  @async_fs.kind(value) is Directory
}

///|
fn relative_to_base(base : String, value : String) -> String? {
  let root = resolve_path(base, ".")
  let candidate = resolve_path(base, value)
  let relative = relative_path(root, candidate).replace_all(old="\\", new="/")
  if relative == "" {
    Some(".")
  } else if relative == ".." || relative.has_prefix("../") {
    None
  } else {
    Some(relative)
  }
}

///|
fn glob_tree_root(value : String) -> String? {
  let normalized = value.replace_all(old="\\", new="/")
  if normalized.has_suffix("/**") {
    Some(value.unsafe_substring(start=0, end=value.length() - 3).to_string())
  } else {
    None
  }
}

///|
fn bundle_host_from_platform(
  platform : String,
) -> BundleHost raise BundleRuntimeError {
  if platform.has_prefix("darwin-") {
    Macos
  } else if platform.has_prefix("win32-") {
    Windows
  } else if platform.has_prefix("linux-") {
    Linux
  } else {
    raise UnsupportedPlatform(platform~)
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
      if path_exists(path) {
        return
      }
      raise BundleFileSystemError::CreateDirectory(
        path~,
        detail=@debug.render(Repr(error)),
      )
    }
  }
}

///|
async fn copy_macos_file(source : String, destination : String) -> Unit {
  ensure_dir(path_parent(destination))
  let code = @process.run("ditto", [source, destination]) catch {
    error =>
      raise BundleFileSystemError::Copy(
        source~,
        destination~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise BundleToolError::Exit(tool="ditto", code~, detail=source)
  }
}

///|
async fn write_text(path : String, text : String) -> Unit {
  @async_fs.write_file(path, text, create_mode=CreateOrTruncate) catch {
    error =>
      raise BundleFileSystemError::Write(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
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
fn macho_thin_filetype(data : Bytes) -> Int? {
  guard data.length() >= 16 else { return None }
  let magic = macho_u32_le(data, 0)
  guard magic == 0xfeedfacf || magic == 0xfeedface else { return None }
  Some(macho_u32_le(data, 12))
}

///|
async fn require_launchable_macho(path : String) -> Unit {
  let data = @async_fs.read_file(path) catch {
    error =>
      raise BundleFileSystemError::Read(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard macho_thin_filetype(data.binary()) is Some(filetype) else { return }
  guard filetype != MachoExecute else { return }
  raise BundlePlanError::NotLaunchableMachO(path~, filetype~)
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
fn helper_info_plist(
  spec : ProtonBundleSpec,
  helper : MacosHelperSpec,
) -> String raise @packager.PackagePlanError {
  let (macos_version, bundle_version) = @packager.macos_versions(
    spec.package_spec.version,
  )
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
  .replace_all(old="{{MACOS_VERSION}}", new=xml_escape(macos_version))
  .replace_all(old="{{BUNDLE_VERSION}}", new=xml_escape(bundle_version))
}

///|
async fn stage_update_revision(
  spec : ProtonBundleSpec,
  destination : String,
) -> Unit {
  write_text(
    resolve_path(destination, "proton-update-revision"),
    "\{spec.update_revision}\n",
  )
}

///|
async fn write_package_manifest(
  spec : ProtonBundleSpec,
  destination : String,
  kind : String,
  host : BundleHost,
) -> Unit {
  let bundle_version = match host {
    Macos => @packager.macos_versions(spec.package_spec.version).1
    Windows | Linux => spec.package_spec.version
  }
  let manifest : Json = {
    "schema_version": 1,
    "kind": kind,
    "product_name": spec.package_spec.product_name,
    "identifier": spec.package_spec.identifier,
    "version": spec.package_spec.version,
    "bundle_version": bundle_version,
    "targets": spec.package_spec.formats.map(fn(format) { format.to_string() }),
    "url_schemes": spec.package_spec.url_schemes,
    "document_types": spec.package_spec.document_types.map(fn(
      document_type,
    ) -> Json {
      {
        "name": document_type.name(),
        "extensions": document_type.extensions(),
        "role": document_type.role(),
      }
    }),
  }
  write_text(
    resolve_path(destination, "proton-package.json"),
    manifest.stringify() + "\n",
  )
}
