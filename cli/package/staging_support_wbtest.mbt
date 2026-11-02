///|
fn test_staging_plan(
  root : String,
  sign_binaries~ : Array[String] = [],
) -> PackagePlan {
  PackagePlan::{
    root,
    config: @proton_config.AppConfig(
      "dev.proton.demo",
      package_config=Some(@proton_config.PackageConfig("Demo & App", "1.2.3")),
    ),
    app_package: "app",
    config_path: resolve_path(root, "proton.project.json"),
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    formats: [@packager.PackageFormat::App],
    output: resolve_path(root, "dist"),
    base_dir: root,
    frontend_dist: None,
    resources: [],
    sign_binaries,
    release: true,
    prepare: None,
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_minimum_system_version: None,
    nsis_install_mode: @packager.NsisInstallMode::CurrentUser,
    sign: false,
    notarize: false,
  }
}

///|
test "resolved runtime platform selects the Proton package layout" {
  assert_true(staging_host_from_platform("darwin-arm64") == Macos)
  assert_true(staging_host_from_platform("win32-x64") == Windows)
  assert_true(staging_host_from_platform("linux-x64") == Linux)
  try ignore(staging_host_from_platform("freebsd-x64")) catch {
    StagingRuntimeError::UnsupportedPlatform(platform~) =>
      assert_eq(platform, "freebsd-x64")
    _ => abort("expected an unsupported platform error")
  } noraise {
    _ => abort("expected an unsupported platform error")
  }
}

///|
test "macOS bundle defines the complete CEF helper family" {
  let helpers = macos_helper_specs("Demo & App", "dev.proton.demo")
  @debug.assert_eq(helpers.map(fn(helper) { helper.bundle_name }), [
    "Demo & App Helper", "Demo & App Helper (Alerts)", "Demo & App Helper (GPU)",
    "Demo & App Helper (Plugin)", "Demo & App Helper (Renderer)",
  ])
  @debug.assert_eq(helpers.map(fn(helper) { helper.bundle_identifier }), [
    "dev.proton.demo.helper", "dev.proton.demo.helper.alerts", "dev.proton.demo.helper.gpu",
    "dev.proton.demo.helper.plugin", "dev.proton.demo.helper.renderer",
  ])
  for helper in helpers {
    assert_eq(helper.executable_name, helper.bundle_name)
  }
}

///|
test "macOS helper plist matches its bundle identity" {
  let spec = test_staging_plan(".")
  let helper = macos_helper_specs(
      "Demo & {{IDENTIFIER}} {{NAME}}",
      spec.identifier,
    )[4]
  let plist = helper_info_plist(spec, helper)
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>Demo &amp; {{IDENTIFIER}} {{NAME}} Helper (Renderer)</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>dev.proton.demo.helper.renderer</string>",
    ),
  )
  assert_true(
    plist.contains("<key>CFBundleVersion</key><string>1.2.3</string>"),
  )
}

///|
test "thin Mach-O headers expose their filetype" {
  let executable = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x02\x00\x00\x00"
  let dsym = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x0a\x00\x00\x00"
  let thin32 = b"\xce\xfa\xed\xfe\x0c\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x00"
  assert_eq(macho_thin_filetype(executable), Some(0x2))
  assert_eq(macho_thin_filetype(dsym), Some(0xa))
  assert_eq(macho_thin_filetype(thin32), Some(0x6))
}

///|
test "unrecognized executable formats are not rejected as Mach-O" {
  let fat = b"\xca\xfe\xba\xbe\x00\x00\x00\x02\x01\x00\x00\x0c\x00\x00\x00\x00"
  assert_eq(macho_thin_filetype(fat), None)
  assert_eq(macho_thin_filetype(b"#!/bin/sh\necho hi\n"), None)
  assert_eq(macho_thin_filetype(b"\xcf\xfa\xed\xfe"), None)
}

///|
test "Mach-O rejection reports the discovered filetype" {
  inspect(
    StagingPlanError::NotLaunchableMachO(
      path="SeekMoon.app/Contents/MacOS/seekmoon",
      filetype=0xa,
    ).message(),
    content="bundle executable SeekMoon.app/Contents/MacOS/seekmoon is a Mach-O of type MH_DSYM, not MH_EXECUTE",
  )
}

///|

///|
async test "packaged configuration retains frontend and platform fields" {
  let root = @async_fs.tmpdir(prefix="proton-package-config-")
  defer @async_fs.rmdir(root, recursive=true)
  let config = @proton_config.AppConfig::parse(
    (
      #|{"identifier":"com.example.package","backend":{"path":".","package":"app1"},"frontend":{"dev_url":"http://localhost:4300","path":"ui","dist":"dist"},"package":{"product_name":"Original","version":"1.0.0","formats":["app"]}}
    ),
  )
  let format = match @packager.current_package_host() {
    Macos | Windows => "zip"
    Linux => "appimage"
  }
  let plan = build_package_plan(
    parse_package_args([
      "--product-name", "Renamed", "--version", "2.0.0", "--package", "app2", "--nsis-install-mode",
      "perMachine", "--macos-minimum-system-version", "16.0", "--format", format,
    ]),
    resolve_path(root, "proton.project.json"),
    config,
  )
  stage_update_version(plan, root)
  assert_eq(
    @async_fs.read_file(resolve_path(root, "proton-update-version")).text(),
    "2.0.0\n",
  )
  write_package_manifest(plan, root)
  let loaded = @proton_config.AppConfig::load(
    resolve_path(root, "proton-package.json"),
  )
  assert_eq(loaded, plan.config)
  assert_eq(loaded.frontend, config.frontend)
  assert_eq(loaded.backend.unwrap().app_package, "app2")
  assert_eq(config.backend.unwrap().app_package, "app1")
  let packaged = loaded.package_config.unwrap()
  assert_eq(packaged.formats, [format])
  assert_eq(packaged.formats, plan.formats.map(format => format.to_string()))
  assert_eq(
    packaged.nsis_install_mode,
    if @packager.current_package_host() == Windows {
      Some("perMachine")
    } else {
      None
    },
  )
  assert_eq(
    packaged.minimum_system_version,
    if @packager.current_package_host() == Macos {
      Some("16.0")
    } else {
      None
    },
  )
  assert_eq(config.package_config.unwrap().nsis_install_mode, None)
  assert_eq(loaded.package_config.unwrap().product_name, "Renamed")
  assert_eq(loaded.package_config.unwrap().version, "2.0.0")
  assert_eq(plan.frontend_dist, Some(resolve_path(root, "ui/dist")))
}

///|
test "macOS signing turns a directory tree into a scanned target" {
  let root = "/tmp/proton-sign-tree"
  let plan = test_staging_plan(root, sign_binaries=[
    resolve_path(root, "payload/**"),
    resolve_path(root, "bin/tool"),
  ])
  let targets = macos_package_sign_targets(plan).filter(target => {
    target.path.has_prefix("Contents/Resources/payload") ||
    target.path.has_prefix("Contents/Resources/bin")
  })
  assert_eq(targets.length(), 2)
  assert_eq(targets[0].path, "Contents/Resources/payload")
  assert_true(targets[0].tree)
  assert_true(targets[0].entitlements)
  assert_eq(targets[1].path, "Contents/Resources/bin/tool")
  assert_false(targets[1].tree)
}

///|
test "macOS signing rejects any other glob" {
  let root = "/tmp/proton-sign-tree"
  let glob = resolve_path(root, "payload/*.dylib")
  let plan = test_staging_plan(root, sign_binaries=[glob])
  try ignore(macos_package_sign_targets(plan)) catch {
    StagingPlanError::UnsupportedSignGlob(path~) => assert_eq(path, glob)
    _ => fail("expected an unsupported signing glob")
  } noraise {
    _ => fail("expected the signing glob to be rejected")
  }
}
