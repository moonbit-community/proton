///|
fn parse_package_args(args : Array[String]) -> RawPackageOptions raise {
  package_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
test "NSIS mode resolves CLI override before Windows configuration and default" {
  let defaults = @proton_config.ProjectPackageConfig("Demo", "1.0.0")
  let arguments = parse_package_args([]).package_args
  assert_eq(
    resolve_nsis_install_mode(arguments, defaults),
    @packager.NsisInstallMode::CurrentUser,
  )
  for
    entry in [
      ("currentUser", @packager.NsisInstallMode::CurrentUser),
      ("perMachine", @packager.NsisInstallMode::PerMachine),
      ("both", @packager.NsisInstallMode::Both),
    ] {
    let (name, mode) = entry
    let configured = @proton_config.ProjectPackageConfig(
      "Demo",
      "1.0.0",
      platforms=@proton_config.ProjectPackagePlatforms(
        windows=@proton_config.ProjectPlatformPackageConfig(
          nsis_install_mode=name,
        ),
      ),
    )
    assert_eq(resolve_nsis_install_mode(arguments, configured), mode)
    let cli_arguments = parse_package_args([
        "--nsis-install-mode", "currentUser",
      ]).package_args
    assert_eq(
      resolve_nsis_install_mode(cli_arguments, configured),
      @packager.NsisInstallMode::CurrentUser,
    )
  }
}

///|
test "parse package args accepts repeated formats and overrides" {
  let raw = parse_package_args([
    "--package", "desktop", "--format", "app", "--format", "zip", "--format", "dmg",
    "--output", "dist", "--product-name", "Demo", "--version", "1.2.3", "--icon",
    "app.icns", "--url-scheme", "demo", "--dry-run",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.package_args.formats, [
    @packager.PackageFormat::App,
    @packager.PackageFormat::Zip,
    @packager.PackageFormat::Dmg,
  ])
  @debug.assert_eq(raw.package_args.output, Some("dist"))
  assert_eq(raw.package_args.product_name, Some("Demo"))
  assert_eq(raw.package_args.identifier, None)
  assert_eq(raw.package_args.version, Some("1.2.3"))
  assert_eq(raw.package_args.icons, ["app.icns"])
  assert_eq(raw.package_args.url_schemes, ["demo"])
  assert_false(raw.release)
  assert_true(raw.dry_run)
}

///|
test "project package resolves platform overrides exactly" {
  let package_config = @proton_config.ProjectPackageConfig(
    "Demo",
    "1.2.3",
    formats=["app"],
    resources=["assets/common"],
    sign=Some(@proton_config.ProjectSignConfig(binaries=["helpers/common"])),
    platforms=@proton_config.ProjectPackagePlatforms(
      macos=@proton_config.ProjectPlatformPackageConfig(
        formats=["app", "dmg"],
        resources=["assets/macos"],
        sign=@proton_config.ProjectSignConfig(binaries=["helpers/macos"]),
      ),
      windows=@proton_config.ProjectPlatformPackageConfig(resources=[
        "assets/windows",
      ]),
      linux=@proton_config.ProjectPlatformPackageConfig(formats=[]),
    ),
  )
  assert_eq(
    resolve_platform_package_config(
      package_config,
      @packager.PackageHost::Macos,
    ),
    ResolvedPlatformPackageConfig::{
      formats: ["app", "dmg"],
      resources: ["assets/common", "assets/macos"],
      sign_binaries: ["helpers/common", "helpers/macos"],
    },
  )
  assert_eq(
    resolve_platform_package_config(
      package_config,
      @packager.PackageHost::Windows,
    ),
    ResolvedPlatformPackageConfig::{
      formats: ["app"],
      resources: ["assets/common", "assets/windows"],
      sign_binaries: ["helpers/common"],
    },
  )
  assert_eq(
    resolve_platform_package_config(
      package_config,
      @packager.PackageHost::Linux,
    ),
    ResolvedPlatformPackageConfig::{
      formats: [],
      resources: ["assets/common"],
      sign_binaries: ["helpers/common"],
    },
  )
}

///|
test "project packaging rejects an identifier override" {
  try parse_package_args(["--identifier", "com.example.demo"]) catch {
    error =>
      assert_true(
        error.to_string().contains("unexpected argument '--identifier'"),
      )
  } noraise {
    _ => abort("expected --identifier to be rejected")
  }
}

///|
test "parse package args enables release builds explicitly" {
  let raw = parse_package_args(["--release"])
  assert_true(raw.release)
}

///|
test "package no longer accepts an implicit cached executable" {
  try parse_package_args(["--no-build"]) catch {
    error =>
      assert_true(
        error.to_string().contains("unexpected argument '--no-build'"),
      )
  } noraise {
    _ => abort("expected --no-build to be rejected")
  }
}

///|
test "parse package args rejects unsupported format" {
  try parse_package_args(["--format", "msi"]) catch {
    @packager.PackagePlanError::UnsupportedFormat(format="msi") => ()
    _ => abort("expected unsupported format")
  } noraise {
    _ => abort("expected unsupported format")
  }
}

///|
test "updater revision is explicit, positive and full width" {
  assert_eq(parse_package_args([]).update_revision, 0UL)
  let maximum = "18446744073709551615"
  assert_eq(
    parse_package_args(["--updater-revision", maximum]).update_revision,
    18446744073709551615UL,
  )
  try
    parse_package_args(["--updater-base-url", "https://example.com/releases"])
  catch {
    error => assert_true(error.to_string().contains("updater-revision"))
  } noraise {
    _ => abort("expected the updater revision to be required")
  }
  for expected in ["0", "-1", "1.5", "not-a-number"] {
    try parse_package_args(["--updater-revision", expected]) catch {
      InvalidRevision(value~) => assert_eq(value, expected)
      _ => abort("expected an invalid updater revision")
    } noraise {
      _ => abort("expected the updater revision to be rejected")
    }
  }
}

///|
test "updater metadata options form one complete value" {
  let raw = parse_package_args([
    "--updater-base-url", "https://example.com/releases", "--updater-published-at",
    "2026-08-25T00:00:00Z", "--updater-revision", "42",
  ])
  assert_eq(
    raw.updater_metadata,
    Some(UpdaterMetadataOptions::{
      base_url: "https://example.com/releases",
      published_at: "2026-08-25T00:00:00Z",
    }),
  )
  assert_eq(raw.update_revision, 42UL)
  try
    parse_package_args([
      "--updater-base-url", "https://example.com/releases", "--updater-revision",
      "42",
    ])
  catch {
    error => assert_true(error.to_string().contains("updater-published-at"))
  } noraise {
    _ => abort("expected updater metadata to require a publication instant")
  }
}

///|
test "notarize implies signing" {
  let raw = parse_package_args(["--notarize", "--dry-run"])
  assert_true(raw.package_args.sign)
  assert_true(raw.package_args.notarize)
  assert_true(raw.dry_run)
}

///|
test "sign does not require notarization" {
  let raw = parse_package_args(["--sign"])
  assert_true(raw.package_args.sign)
  assert_false(raw.package_args.notarize)
}

///|
#cfg(not(platform="windows"))
test "macOS package paths normalize absolute and relative inputs" {
  let base = @fsutil.resolve_path("fixtures", "proton package path base")
  assert_eq(@fsutil.resolve_path(base, "/"), "/")
  assert_eq(
    @fsutil.resolve_path(base, "/tmp/proton absolute path"),
    "/tmp/proton absolute path",
  )
  assert_eq(
    @fsutil.resolve_path(base, "relative/file.txt"),
    base + "/relative/file.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, "proton.project.json"),
    base + "/proton.project.json",
  )
  assert_eq(
    @fsutil.resolve_path(base, "directory with spaces/file.txt"),
    base + "/directory with spaces/file.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, "../sibling"),
    @fsutil.resolve_path(@fsutil.path_parent(base), "sibling"),
  )
  assert_eq(
    @fsutil.resolve_path(base, "nested\\child.txt"),
    base + "/nested\\child.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, "\\tmp\\proton path"),
    base + "/\\tmp\\proton path",
  )
}
