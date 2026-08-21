///|
fn parse_package_args(args : Array[String]) -> RawPackageOptions raise {
  package_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
fn parse_package_matches(args : Array[String]) -> @argparse.Matches raise {
  command().parse(argv=args, env=Map([]))
}

///|
test "parse package args accepts repeated targets and overrides" {
  let raw = parse_package_args([
    "--package", "desktop", "--target", "app", "--target", "zip", "--target", "dmg",
    "--output", "dist", "--dry-run",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.targets, ["app", "zip", "dmg"])
  @debug.assert_eq(raw.output, Some("dist"))
  assert_false(raw.release)
  assert_true(raw.dry_run)
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
test "parse package args rejects unsupported target" {
  try parse_package_args(["--target", "msi"]) catch {
    PackageUsageError::UnsupportedTarget(target="msi") => ()
    _ => abort("expected unsupported target")
  } noraise {
    _ => abort("expected unsupported target")
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
  assert_true(raw.sign)
  assert_true(raw.notarize)
  assert_true(raw.dry_run)
}

///|
test "sign does not require notarization" {
  let raw = parse_package_args(["--sign"])
  assert_true(raw.sign)
  assert_false(raw.notarize)
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

///|
test "macOS package metadata validation rejects unsafe values" {
  try validate_product_name("Demo/App") catch {
    PackagePlanError::InvalidProductName(reason~) =>
      assert_true(reason.contains("path-unsafe character"))
    _ => abort("expected unsafe product name")
  } noraise {
    _ => abort("expected unsafe product name")
  }
  try validate_product_name("Demo\nApp") catch {
    PackagePlanError::InvalidProductName(reason~) =>
      assert_true(reason.contains("ASCII control character"))
    _ => abort("expected control character error")
  } noraise {
    _ => abort("expected control character error")
  }
  try validate_bundle_identifier("demo") catch {
    PackagePlanError::InvalidIdentifier(identifier="demo", reason~) =>
      assert_true(reason.contains("reverse-DNS"))
    _ => abort("expected reverse-DNS identifier error")
  } noraise {
    _ => abort("expected reverse-DNS identifier error")
  }
  try validate_bundle_identifier("com.example.bad_value") catch {
    PackagePlanError::InvalidIdentifier(
      identifier="com.example.bad_value",
      reason~
    ) => assert_true(reason.contains("unsupported character"))
    _ => abort("expected identifier character error")
  } noraise {
    _ => abort("expected identifier character error")
  }
}
