///|
fn macos_dmg_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(plan.output, plan.product_name + ".dmg")
}

///|
fn macos_dmg_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging.dmg",
  )
}

///|
fn macos_dmg_root_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".dmg-root",
  )
}

///|
async fn create_macos_dmg(plan : PackagePlan, app : String) -> String {
  let root = macos_dmg_root_path(plan)
  let staging = macos_dmg_staging_path(plan)
  remove_tree(root)
  remove_tree(staging)
  ensure_dir(root)
  create_macos_dmg_impl(plan, app, root, staging) catch {
    error => {
      remove_tree(root) catch {
        _ => ()
      }
      remove_tree(staging) catch {
        _ => ()
      }
      raise error
    }
  }
  remove_tree(root)
  if plan.sign {
    sign_macos_dmg(plan, staging)
  }
  verify_macos_dmg(staging)
  staging
}

///|
async fn create_macos_dmg_impl(
  plan : PackagePlan,
  app : String,
  root : String,
  staging : String,
) -> Unit {
  copy_tree(app, @fsutil.resolve_path(root, plan.product_name + ".app"))
  let applications = @fsutil.resolve_path(root, "Applications")
  @async_fs.symlink(target="/Applications", applications) catch {
    error =>
      raise PackageFileSystemError::Write(
        path=applications,
        detail=@debug.render(Repr(error)),
      )
  }
  run_hdiutil(
    [
      "create",
      "-volname",
      plan.product_name,
      "-srcfolder",
      root,
      "-format",
      "UDZO",
      "-ov",
      staging,
    ],
    stage="create DMG",
  )
}

///|
async fn sign_macos_dmg(plan : PackagePlan, dmg : String) -> Unit {
  let identity = required_macos_signing_identity()
  ignore(validate_macos_signing_identity(identity, notarize=plan.notarize))
  codesign_target(
    identity,
    dmg,
    runtime_options=false,
    deep=false,
    entitlements=None,
  )
  verify_macos_codesign_target(dmg, deep=false)
}

///|
async fn notarize_macos_dmg(app : String, dmg : String) -> Unit {
  let profile = required_macos_notary_profile()
  submit_macos_notarization_artifact(dmg, profile)
  staple_macos_artifact(dmg)
  staple_macos_artifact(app)
  validate_macos_staple(dmg)
  validate_macos_staple(app)
  verify_macos_dmg(dmg)
  assess_macos_app(app)
}

///|
async fn verify_macos_dmg(dmg : String) -> Unit {
  run_hdiutil(["verify", dmg], stage="verify DMG")
}

///|
async fn run_hdiutil(args : Array[String], stage~ : String) -> Unit {
  let code = @process.run("/usr/bin/hdiutil", args) catch {
    error =>
      raise MacosSigningError::ToolFailure(
        stage~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise MacosSigningError::ToolFailure(
      stage~,
      detail="exit code " + code.to_string(),
    )
  }
}
