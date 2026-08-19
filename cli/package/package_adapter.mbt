///|
async fn package_spec(
  plan : PackagePlan,
  executable : String,
  helper : String,
  runtime : String,
) -> @packager.PackageSpec {
  let host = current_package_host()
  let payloads = package_payloads(plan, helper, runtime, host)
  let formats = plan.targets.map(target => {
    @packager.PackageFormat::parse(target)
  })
  let document_types = plan.document_types.map(document_type => {
    @packager.DocumentType::new(
      document_type.name,
      document_type.extensions.copy(),
      role=document_type.role,
    )
  })
  @packager.PackageSpec::new(
    executable,
    plan.product_name,
    plan.identifier,
    plan.version,
    formats,
    plan.output,
    payloads~,
    icons=plan.icons.copy(),
    url_schemes=plan.url_schemes.copy(),
    document_types~,
    sign=plan.sign,
    notarize=plan.notarize,
  )
}

///|
async fn package_payloads(
  plan : PackagePlan,
  helper : String,
  runtime : String,
  host : PackageHost,
) -> Array[@packager.Payload] {
  let payloads : Array[@packager.Payload] = []
  match host {
    Macos | Linux => {
      payloads.push(
        @packager.Payload::new(
          runtime,
          "proton",
          location=@packager.PayloadLocation::Resources,
        ),
      )
      if host == Linux {
        payloads.push(
          @packager.Payload::new(
            helper,
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
          @packager.Payload::new(
            @fsutil.resolve_path(runtime, "bin/" + name),
            name,
            location=@packager.PayloadLocation::Executables,
          ),
        )
      }
      for name in windows_runtime_root_data_files() {
        payloads.push(
          @packager.Payload::new(
            @fsutil.resolve_path(runtime, "bin/" + name),
            name,
            location=@packager.PayloadLocation::Executables,
          ),
        )
      }
      payloads.push(
        @packager.Payload::new(
          @fsutil.resolve_path(runtime, "Resources"),
          ".",
          location=@packager.PayloadLocation::Resources,
        ),
      )
      payloads.push(
        @packager.Payload::new(
          helper,
          "cef_process.exe",
          location=@packager.PayloadLocation::Executables,
        ),
      )
    }
  }
  let location = @packager.PayloadLocation::Resources
  for payload in project_payloads(plan, location) {
    payloads.push(payload)
  }
  payloads
}

///|
async fn project_payloads(
  plan : PackagePlan,
  location : @packager.PayloadLocation,
) -> Array[@packager.Payload] {
  let inputs : Array[String] = []
  match plan.frontend_dist {
    Some(path) => inputs.push(path)
    None => ()
  }
  inputs.append(plan.resources)
  let copied : Map[String, Bool] = Map([])
  let payloads : Array[@packager.Payload] = []
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
    payloads.push(@packager.Payload::new(source, relative, location~))
  }
  payloads
}

///|
fn package_customization(
  plan : PackagePlan,
) -> @packager.PackageCustomization raise PackagePlanError {
  @packager.PackageCustomization::new(
    macos_plist_strings=[
      @packager.MacosPlistString::new(
        "ProtonUpdateRevision",
        plan.update_revision.to_string(),
      ),
    ],
    macos_sign_targets=macos_package_sign_targets(plan),
    windows_sign_targets=windows_package_sign_targets(plan),
    windows_verify_targets=["d3dcompiler_47.dll", "dxil.dll"],
    linux_resources_path="usr/Resources",
  )
}

///|
fn macos_package_sign_targets(
  plan : PackagePlan,
) -> Array[@packager.MacosSignTarget] raise PackagePlanError {
  let prefix = "Contents/Resources/proton"
  let framework = prefix + "/Frameworks/Chromium Embedded Framework.framework"
  let targets = [
    @packager.MacosSignTarget::new(framework + "/Libraries/libEGL.dylib"),
    @packager.MacosSignTarget::new(framework + "/Libraries/libGLESv2.dylib"),
    @packager.MacosSignTarget::new(
      framework + "/Libraries/libcef_sandbox.dylib",
    ),
    @packager.MacosSignTarget::new(
      framework + "/Libraries/libvk_swiftshader.dylib",
    ),
    @packager.MacosSignTarget::new(framework),
    @packager.MacosSignTarget::new(prefix + "/bin/libEGL.dylib"),
    @packager.MacosSignTarget::new(prefix + "/bin/libGLESv2.dylib"),
    @packager.MacosSignTarget::new(prefix + "/bin/libvk_swiftshader.dylib"),
  ]
  for binary in plan.sign_binaries {
    match relative_to_base(plan.base_dir, binary) {
      Some(relative) =>
        targets.push(
          @packager.MacosSignTarget::new(
            "Contents/Resources/" + relative,
            entitlements=true,
          ),
        )
      None => raise PackagePlanError::InputOutsideProject(path=binary)
    }
  }
  for helper in macos_helper_specs(plan.product_name, plan.identifier) {
    targets.push(
      @packager.MacosSignTarget::new(
        "Contents/Frameworks/" + helper.bundle_name + ".app",
        entitlements=true,
      ),
    )
  }
  targets
}

///|
fn windows_package_sign_targets(
  plan : PackagePlan,
) -> Array[String] raise PackagePlanError {
  let targets = ["cef_process.exe"]
  for binary in plan.sign_binaries {
    match relative_to_base(plan.base_dir, binary) {
      Some(relative) => {
        let target = "Resources/" + relative
        if !targets.contains(target) {
          targets.push(target)
        }
      }
      None => raise PackagePlanError::InputOutsideProject(path=binary)
    }
  }
  targets
}

///|
async fn prepare_proton_package(
  plan : PackagePlan,
  helper : String,
  layout : @packager.PackageLayout,
) -> Unit {
  let host = current_package_host()
  let metadata_root = match host {
    Windows => layout.root()
    Macos | Linux => layout.resources()
  }
  stage_update_revision(plan, metadata_root)
  let kind = match host {
    Macos => "macos-app"
    Windows => "windows-portable"
    Linux => "linux-appimage"
  }
  write_package_manifest(plan, metadata_root, kind)
  match host {
    Macos => prepare_macos_proton_package(plan, helper, layout)
    Windows =>
      validate_windows_portable_layout(layout.root(), layout.executable())
    Linux => {
      let staged_helper = @fsutil.resolve_path(
        layout.executables(),
        "cef_process",
      )
      guard @fsutil.path_is_file(staged_helper) else {
        raise PackageRuntimeError::HelperMissing(path=staged_helper)
      }
      set_linux_rpath(layout.executable(), linux_package_rpath)
      set_linux_rpath(staged_helper, linux_package_rpath)
    }
  }
}

///|
async fn prepare_macos_proton_package(
  plan : PackagePlan,
  helper_source : String,
  layout : @packager.PackageLayout,
) -> Unit {
  require_launchable_macho(layout.executable())
  guard @fsutil.path_is_file(helper_source) else {
    raise PackageRuntimeError::HelperMissing(path=helper_source)
  }
  for helper in macos_helper_specs(plan.product_name, plan.identifier) {
    let helper_app = @fsutil.resolve_path(
      layout.libraries(),
      helper.bundle_name + ".app",
    )
    let helper_macos = @fsutil.resolve_path(helper_app, "Contents/MacOS")
    let helper_executable = @fsutil.resolve_path(
      helper_macos,
      helper.executable_name,
    )
    ensure_dir(helper_macos)
    copy_file(helper_source, helper_executable)
    @async_fs.chmod(helper_executable, 0o755)
    require_launchable_macho(helper_executable)
    write_text(
      @fsutil.resolve_path(helper_app, "Contents/Info.plist"),
      helper_info_plist(plan, helper),
    )
  }
}
