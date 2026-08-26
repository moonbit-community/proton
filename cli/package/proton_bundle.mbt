///|
async fn package_spec(
  spec : ProtonBundleSpec,
  runtime : String,
  cef_process : String,
  host : BundleHost,
) -> @packager.PackageSpec {
  let payloads = spec.package_spec.payloads.copy()
  payloads.append(package_payloads(spec, runtime, cef_process, host))
  @packager.PackageSpec(
    spec.package_spec.executable,
    spec.package_spec.product_name,
    spec.package_spec.identifier,
    spec.package_spec.version,
    spec.package_spec.formats,
    spec.package_spec.output,
    payloads~,
    icons=spec.package_spec.icons,
    url_schemes=spec.package_spec.url_schemes,
    document_types=spec.package_spec.document_types,
    sign=spec.package_spec.sign,
    notarize=spec.package_spec.notarize,
  )
}

///|
/// Packages an already-built Proton application using the active immutable
/// runtime and helper installation.
async fn build_proton_package(
  spec : ProtonBundleSpec,
) -> (Array[String], String) {
  guard path_is_file(spec.package_spec.executable) else {
    raise BundleRuntimeError::ExecutableMissing(
      path=spec.package_spec.executable,
    )
  }
  let installation = @cef_store.resolve_default()
  let cef_process = @cef_store.resolve_default_helper()
  guard path_is_file(cef_process) else {
    raise BundleRuntimeError::HelperMissing(path=cef_process)
  }
  let platform = installation.platform()
  let host = bundle_host_from_platform(platform)
  let artifacts = @packager.build_with(
    package_spec(spec, installation.runtime_root(), cef_process, host),
    package_customization(spec),
    async fn(layout) { prepare_proton_package(spec, cef_process, layout, host) },
  )
  (artifacts, platform)
}

///|
async fn package_payloads(
  spec : ProtonBundleSpec,
  runtime : String,
  cef_process : String,
  host : BundleHost,
) -> Array[@packager.Payload] {
  let payloads : Array[@packager.Payload] = []
  match host {
    Macos | Linux => {
      payloads.push(
        @packager.Payload(
          runtime,
          "proton",
          location=@packager.PayloadLocation::Resources,
        ),
      )
      if host == Linux {
        payloads.push(
          @packager.Payload(
            cef_process,
            "cef_process",
            location=@packager.PayloadLocation::Executables,
          ),
        )
      }
    }
    Windows => {
      require_windows_runtime_layout(runtime)
      for name in windows_runtime_binary_files() {
        payloads.push(
          @packager.Payload(
            resolve_path(runtime, "bin/" + name),
            name,
            location=@packager.PayloadLocation::Executables,
          ),
        )
      }
      for name in windows_runtime_root_data_files() {
        payloads.push(
          @packager.Payload(
            resolve_path(runtime, "bin/" + name),
            name,
            location=@packager.PayloadLocation::Executables,
          ),
        )
      }
      payloads.push(
        @packager.Payload(
          resolve_path(runtime, "Resources"),
          ".",
          location=@packager.PayloadLocation::Resources,
        ),
      )
      payloads.push(
        @packager.Payload(
          cef_process,
          "cef_process.exe",
          location=@packager.PayloadLocation::Executables,
        ),
      )
    }
  }
  let location = @packager.PayloadLocation::Resources
  for payload in project_payloads(spec, location) {
    payloads.push(payload)
  }
  payloads
}

///|
async fn project_payloads(
  spec : ProtonBundleSpec,
  location : @packager.PayloadLocation,
) -> Array[@packager.Payload] {
  let inputs : Array[String] = []
  match spec.frontend_dist {
    Some(path) => inputs.push(path)
    None => ()
  }
  inputs.append(spec.resources)
  let copied : Map[String, Bool] = Map([])
  let payloads : Array[@packager.Payload] = []
  for input in inputs {
    guard copied.get(input) is None else { continue }
    copied[input] = true
    let source = match glob_tree_root(input) {
      Some(root) => root
      None if input.contains("*") =>
        raise BundlePlanError::UnsupportedResourceGlob(path=input)
      None => input
    }
    guard path_exists(source) else {
      raise BundlePlanError::MissingInput(path=input)
    }
    let relative = match relative_to_base(spec.base_dir, source) {
      Some(relative) => relative
      None => raise BundlePlanError::InputOutsideBase(path=input)
    }
    payloads.push(@packager.Payload(source, relative, location~))
  }
  payloads
}

///|
fn package_customization(
  spec : ProtonBundleSpec,
) -> @packager.PackageCustomization raise BundlePlanError {
  @packager.PackageCustomization(
    macos_plist_strings=[
      @packager.MacosPlistString(
        "ProtonUpdateRevision",
        spec.update_revision.to_string(),
      ),
    ],
    macos_sign_targets=macos_package_sign_targets(spec),
    windows_sign_targets=windows_package_sign_targets(spec),
    windows_verify_targets=["d3dcompiler_47.dll", "dxil.dll"],
    linux_resources_path="usr/Resources",
  )
}

///|
fn macos_package_sign_targets(
  spec : ProtonBundleSpec,
) -> Array[@packager.MacosSignTarget] raise BundlePlanError {
  let prefix = "Contents/Resources/proton"
  let framework = prefix + "/Frameworks/Chromium Embedded Framework.framework"
  let targets = [
    @packager.MacosSignTarget(framework + "/Libraries/libEGL.dylib"),
    @packager.MacosSignTarget(framework + "/Libraries/libGLESv2.dylib"),
    @packager.MacosSignTarget(framework + "/Libraries/libcef_sandbox.dylib"),
    @packager.MacosSignTarget(framework + "/Libraries/libvk_swiftshader.dylib"),
    @packager.MacosSignTarget(framework),
    @packager.MacosSignTarget(prefix + "/bin/libEGL.dylib"),
    @packager.MacosSignTarget(prefix + "/bin/libGLESv2.dylib"),
    @packager.MacosSignTarget(prefix + "/bin/libvk_swiftshader.dylib"),
  ]
  for binary in spec.sign_binaries {
    match relative_to_base(spec.base_dir, binary) {
      Some(relative) =>
        targets.push(
          @packager.MacosSignTarget(
            "Contents/Resources/" + relative,
            entitlements=true,
          ),
        )
      None => raise BundlePlanError::InputOutsideBase(path=binary)
    }
  }
  for
    helper in macos_helper_specs(
      spec.package_spec.product_name,
      spec.package_spec.identifier,
    ) {
    targets.push(
      @packager.MacosSignTarget(
        "Contents/Frameworks/" + helper.bundle_name + ".app",
        entitlements=true,
      ),
    )
  }
  targets
}

///|
fn windows_package_sign_targets(
  spec : ProtonBundleSpec,
) -> Array[String] raise BundlePlanError {
  let targets = ["cef_process.exe"]
  for binary in spec.sign_binaries {
    match relative_to_base(spec.base_dir, binary) {
      Some(relative) => {
        let target = "Resources/" + relative
        if !targets.contains(target) {
          targets.push(target)
        }
      }
      None => raise BundlePlanError::InputOutsideBase(path=binary)
    }
  }
  targets
}

///|
async fn prepare_proton_package(
  spec : ProtonBundleSpec,
  cef_process : String,
  layout : @packager.PackageLayout,
  host : BundleHost,
) -> Unit {
  let metadata_root = match host {
    Windows => layout.root()
    Macos | Linux => layout.resources()
  }
  stage_update_revision(spec, metadata_root)
  let kind = match host {
    Macos => "macos-app"
    Windows => "windows-portable"
    Linux => "linux-appimage"
  }
  write_package_manifest(spec, metadata_root, kind, host)
  match host {
    Macos => prepare_macos_proton_package(spec, cef_process, layout)
    Windows =>
      validate_windows_portable_layout(layout.root(), layout.executable())
    Linux => {
      let staged_helper = resolve_path(layout.executables(), "cef_process")
      guard path_is_file(staged_helper) else {
        raise BundleRuntimeError::HelperMissing(path=staged_helper)
      }
      set_linux_rpath(layout.executable(), linux_package_rpath)
      set_linux_rpath(staged_helper, linux_package_rpath)
      let executable_name = host_path(layout.executable()).basename().to_owned()
      let apprun = resolve_path(layout.root(), "AppRun")
      write_text(apprun, proton_linux_apprun(executable_name))
      @async_fs.chmod(apprun, 0o755)
    }
  }
}

///|
async fn prepare_macos_proton_package(
  spec : ProtonBundleSpec,
  cef_process : String,
  layout : @packager.PackageLayout,
) -> Unit {
  require_launchable_macho(layout.executable())
  for
    helper in macos_helper_specs(
      spec.package_spec.product_name,
      spec.package_spec.identifier,
    ) {
    let helper_app = resolve_path(
      layout.libraries(),
      helper.bundle_name + ".app",
    )
    let helper_macos = resolve_path(helper_app, "Contents/MacOS")
    let helper_executable = resolve_path(helper_macos, helper.executable_name)
    ensure_dir(helper_macos)
    copy_macos_file(cef_process, helper_executable)
    @async_fs.chmod(helper_executable, 0o755)
    require_launchable_macho(helper_executable)
    write_text(
      resolve_path(helper_app, "Contents/Info.plist"),
      helper_info_plist(spec, helper),
    )
  }
}
