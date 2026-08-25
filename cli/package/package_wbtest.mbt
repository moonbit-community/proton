///|
fn parse_package_args(args : Array[String]) -> RawPackageOptions raise {
  package_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
fn parse_package_matches(args : Array[String]) -> @argparse.Matches raise {
  command().parse(argv=args, env=Map([]))
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
  assert_eq(updater_revision_from_matches(parse_package_matches([]), None), 0UL)
  let maximum = "18446744073709551615"
  let matches = parse_package_matches(["--updater-revision", maximum])
  assert_eq(
    updater_revision_from_matches(matches, None),
    18446744073709551615UL,
  )
  let no_revision = parse_package_matches([])
  try
    ignore(
      updater_revision_from_matches(
        no_revision,
        Some("https://example.com/releases"),
      ),
    )
  catch {
    MissingRevision => ()
    _ => abort("expected a missing updater revision")
  } noraise {
    _ => abort("expected the updater revision to be required")
  }
  for expected in ["0", "-1", "1.5", "not-a-number"] {
    let invalid = parse_package_matches(["--updater-revision", expected])
    try ignore(updater_revision_from_matches(invalid, None)) catch {
      InvalidRevision(value~) => assert_eq(value, expected)
      _ => abort("expected an invalid updater revision")
    } noraise {
      _ => abort("expected the updater revision to be rejected")
    }
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
