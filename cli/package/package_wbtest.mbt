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
    @fsutil.resolve_path(base, ".proton/runtime.json"),
    base + "/.proton/runtime.json",
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

///|
test "release project config disables only the top-level debug field" {
  let source =
    #|{
    #|  "product_name": "MoonBit 桌面应用",
    #|  "window": {
    #|    "title": "debug = true",
    #|    "width": 800,
    #|    "height": 600
    #|  },
    #|  "entry": {
    #|    "kind": "html",
    #|    "value": "<p>debug = true</p>"
    #|  },
    #|  "debug": true,
    #|  "bundle": {
    #|    "active": true
    #|  }
    #|}
  let release = release_project_config_text(source)
  assert_true(release.contains("\"title\": \"debug = true\""))
  assert_true(release.contains("\"value\": \"<p>debug = true</p>\""))
  let json = @json.parse(release) catch { error => abort(error.to_string()) }
  guard json is { "debug": false, .. } else {
    abort("expected disabled top-level debug field")
  }
}

///|
test "release project config preserves an already disabled or absent debug field" {
  let disabled = "{\"window\":{\"title\":\"Demo\"},\"debug\":false}\n"
  assert_eq(release_project_config_text(disabled), disabled)
  let absent = "{\"window\":{\"title\":\"Demo\"}}\n"
  assert_eq(release_project_config_text(absent), absent)
}

///|
test "macOS package defines the complete CEF helper family" {
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
  let plan = PackagePlan::{
    root: ".",
    workspace_root: ".",
    app_package: "app",
    config_path: "proton.project.json",
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    macos_version: "1.2.3",
    bundle_version: "42",
    update_revision: 42UL,
    targets: ["app"],
    output: "dist",
    release: false,
    base_dir: ".",
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let helper = macos_helper_specs(plan.product_name, plan.identifier)[4]
  let plist = helper_info_plist(plan, helper)
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>Demo &amp; App Helper (Renderer)</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>dev.proton.demo.helper.renderer</string>",
    ),
  )
  assert_true(plist.contains("<key>CFBundleVersion</key><string>42</string>"))
}

///|
test "a thin Mach-O header yields its filetype" {
  // An arm64 executable and its dSYM mirror: identical for twelve bytes, then
  // MH_EXECUTE (2) against MH_DSYM (10). Nothing cheaper tells them apart —
  // not the magic, not the size, not codesign.
  let executable = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x02\x00\x00\x00"
  let dsym = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x0a\x00\x00\x00"
  assert_eq(macho_thin_filetype(executable), Some(0x2))
  assert_eq(macho_thin_filetype(dsym), Some(0xa))
  // 32-bit thin headers agree up to `filetype`, so one offset reads both.
  let thin32 = b"\xce\xfa\xed\xfe\x0c\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x00"
  assert_eq(macho_thin_filetype(thin32), Some(0x6))
}

///|
test "unjudgeable inputs are left alone rather than failed" {
  // The caller rejects only what it can prove wrong, so a universal binary, a
  // script, and a truncated file all read as None. A format this reader does
  // not understand must never become a packaging failure.
  let fat = b"\xca\xfe\xba\xbe\x00\x00\x00\x02\x01\x00\x00\x0c\x00\x00\x00\x00"
  assert_eq(macho_thin_filetype(fat), None)
  assert_eq(macho_thin_filetype(b"#!/bin/sh\necho hi\n"), None)
  assert_eq(macho_thin_filetype(b"\xcf\xfa\xed\xfe"), None)
}

///|
test "the rejection names the filetype it found" {
  inspect(macho_filetype_name(0x2), content="MH_EXECUTE")
  inspect(macho_filetype_name(0xa), content="MH_DSYM")
  inspect(
    PackagePlanError::NotLaunchableMachO(
      path="SeekMoon.app/Contents/MacOS/seekmoon",
      filetype=0xa,
    ).message(),
    content="staged bundle executable SeekMoon.app/Contents/MacOS/seekmoon is a Mach-O of type MH_DSYM, not MH_EXECUTE; the kernel refuses to spawn it",
  )
}
