///|
fn assert_safe_generated_dir(
  generated_dir : String,
  root : String,
) -> Result[Unit, CliError] {
  let normalized_generated = generated_dir.replace(old="/", new="\\")
  let normalized_root = root.replace(old="/", new="\\")
  let parent = path_parent(normalized_root)
  if normalized_generated == "" ||
    normalized_generated.has_suffix(":\\") ||
    normalized_generated == normalized_root ||
    normalized_generated == parent {
    Err(
      CliError::CommandError(
        "Refusing to replace unsafe generated directory: " + generated_dir,
      ),
    )
  } else {
    Ok(())
  }
}

///|
async fn copy_prebuilt_runtime(
  prebuilt_root : String,
  runtime_dir : String,
) -> Result[Unit, CliError] {
  let bin_dir = path_join(runtime_dir, "bin")
  let lib_dir = path_join(runtime_dir, "lib")
  let include_dir = path_join(runtime_dir, "include")
  match ensure_dir(bin_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match ensure_dir(lib_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match ensure_dir(include_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for relative in proton_prebuilt_relative_files() {
    match
      copy_file(
        path_join(prebuilt_root, relative),
        path_join(runtime_dir, relative),
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  match
    copy_file_if_exists(
      path_join(path_join(prebuilt_root, "include"), "proton_native.h"),
      path_join(include_dir, "proton_native.h"),
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(())
}

///|
async fn copy_cef_runtime(
  cef_root : String,
  runtime_dir : String,
) -> Result[Unit, CliError] {
  match
    copy_tree(path_join(cef_root, "Release"), path_join(runtime_dir, "bin")) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  copy_tree(
    path_join(cef_root, "Resources"),
    path_join(runtime_dir, "Resources"),
  )
}

///|
async fn assemble_runtime(
  root : String,
  platform : ProtonPlatform,
  proton_version : String,
  cef_name : String,
  cef_root : String,
  prebuilt_root : String,
  runtime_dir : String,
  relative_dist : String,
) -> Result[Unit, CliError] {
  match assert_safe_generated_dir(runtime_dir, root) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match remove_tree(runtime_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  println("[INFO] Assembling Proton runtime: " + runtime_dir)
  match copy_prebuilt_runtime(prebuilt_root, runtime_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match copy_cef_runtime(cef_root, runtime_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    write_runtime_metadata(
      root,
      runtime_dir,
      proton_version,
      platform.id,
      cef_name,
      relative_dist,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_runtime_dist(runtime_dir) {
    Ok(_) =>
      validate_active_runtime_manifest(
        root,
        platform.id,
        proton_version,
        relative_dist,
      )
    Err(error) => Err(error)
  }
}
