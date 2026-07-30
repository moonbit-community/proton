///|
#cfg(not(platform="windows"))
fn macos_dmg_test_plan(root : String) -> PackagePlan {
  PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: resolve_path(root, "build"),
    app_package: "app",
    config_path: resolve_path(root, "moon.proton"),
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    targets: ["app", "dmg"],
    output: root,
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_paths: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
}

///|
#cfg(not(platform="windows"))
async test "macOS dmg uses drag-to-install layout and a verified UDZO image" {
  guard is_macos_host() else { return }
  let root = resolve_path("target", "proton-package-dmg-real")
  remove_tree(root)
  let app = resolve_path(root, "Source.app")
  ensure_dir(resolve_path(app, "Contents"))
  write_text(
    resolve_path(app, "Contents/Info.plist"),
    "<?xml version=\"1.0\"?><plist><dict></dict></plist>",
  )
  let plan = macos_dmg_test_plan(root)
  let staging = create_macos_dmg(plan, app)
  assert_eq(staging, macos_dmg_staging_path(plan))
  assert_true(@mbfs.path_exists(staging))
  promote_staged_artifacts([
    StagedArtifact::{ staging, destination: macos_dmg_path(plan) },
  ])
  assert_true(@mbfs.path_exists(macos_dmg_path(plan)))
  assert_false(@mbfs.path_exists(macos_dmg_root_path(plan)))
  remove_tree(root)
}
