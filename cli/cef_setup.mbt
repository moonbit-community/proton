///|
fn cef_setup_arg_parser() -> @argparse.Command {
  @argparse.Command(
    "proton cef setup",
    about="Install the Windows Proton runtime into .proton",
    options=[
      OptionArg("name", about="CEF binary directory/archive name"),
      OptionArg("url", about="Full CEF archive URL"),
    ],
  )
}

///|
let default_cef_name = "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal"

///|
let default_cef_base_url = "https://cef-builds.spotifycdn.com"

///|
let proton_version = "0.1.2"

///|
fn path_exists(path : String) -> Bool {
  @mbfs.path_exists(path)
}

///|
fn path_is_dir(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn path_is_file(path : String) -> Bool {
  @mbfs.is_file(path) catch {
    _ => false
  }
}

///|
fn path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + child
  } else {
    base + "\\" + child
  }
}

///|
fn path_parent(path : String) -> String {
  let normalized = path.replace(old="/", new="\\")
  let parts = normalized.split("\\").collect()
  if parts.length() <= 1 {
    normalized
  } else {
    let parent_parts = parts[:parts.length() - 1].to_owned()
    parent_parts.join("\\")
  }
}

///|
fn platform_id() -> String {
  "win32-x64"
}

///|
fn proton_runtime_id(cef_name : String) -> String {
  let cef_version = cef_name
    .replace(old="cef_binary_", new="")
    .replace(old="_windows64_minimal", new="")
  "proton-" + proton_version + "_cef-" + cef_version
}

///|
fn relative_runtime_dist(platform : String, cef_name : String) -> String {
  path_join(
    path_join(path_join(".proton", "runtimes"), platform),
    proton_runtime_id(cef_name),
  )
}

///|
fn source_cef_relative_files() -> Array[String] {
  [
    "include\\capi\\cef_app_capi.h", "include\\capi\\cef_browser_capi.h", "include\\capi\\cef_client_capi.h",
    "include\\capi\\cef_v8_capi.h", "Release\\libcef.lib", "Release\\libcef.dll",
    "Resources\\icudtl.dat",
  ]
}

///|
fn installed_cef_relative_files() -> Array[String] {
  let files = source_cef_relative_files()
  files.push("Release\\icudtl.dat")
  files.push("Release\\chrome_100_percent.pak")
  files.push("Release\\chrome_200_percent.pak")
  files.push("Release\\resources.pak")
  files
}

///|
fn proton_prebuilt_relative_files() -> Array[String] {
  ["bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib"]
}

///|
fn runtime_required_relative_files() -> Array[String] {
  [
    "bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib", "bin\\libcef.dll",
    "bin\\icudtl.dat", "Resources\\icudtl.dat", "Resources\\locales",
  ]
}

///|
fn all_exist(root : String, files : Array[String]) -> Bool {
  for file in files {
    guard path_exists(path_join(root, file)) else { return false }
  }
  true
}

///|
fn has_source_cef_files(root : String) -> Bool {
  all_exist(root, source_cef_relative_files())
}

///|
fn validate_cef_root(root : String) -> Result[Unit, CliError] {
  let missing : Array[String] = []
  for relative in installed_cef_relative_files() {
    let path = path_join(root, relative)
    if !path_exists(path) {
      missing.push(path)
    }
  }
  let version_path = path_join(root, "version.txt")
  if !path_exists(version_path) {
    missing.push(version_path)
  }
  if missing.length() > 0 {
    Err(
      CliError::CommandError(
        "Invalid CEF root: " + root + "\nMissing:\n" + missing.join("\n"),
      ),
    )
  } else {
    Ok(())
  }
}

///|
fn validate_runtime_dist(root : String) -> Result[Unit, CliError] {
  let missing : Array[String] = []
  for relative in runtime_required_relative_files() {
    let path = path_join(root, relative)
    if !path_exists(path) {
      missing.push(path)
    }
  }
  if missing.length() > 0 {
    Err(
      CliError::CommandError(
        "Invalid Proton runtime: " + root + "\nMissing:\n" + missing.join("\n"),
      ),
    )
  } else {
    Ok(())
  }
}

///|
async fn copy_file(src : String, dest : String) -> Result[Unit, CliError] {
  let data = @async_fs.read_file(src) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to read " + src + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @async_fs.write_file(dest, data, create_mode=CreateOrTruncate) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to copy " +
          src +
          " to " +
          dest +
          ": " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn copy_file_if_exists(
  src : String,
  dest : String,
) -> Result[Unit, CliError] {
  guard path_exists(src) else { return Ok(()) }
  copy_file(src, dest)
}

///|
async fn copy_tree(src : String, dest : String) -> Result[Unit, CliError] {
  if path_is_file(src) {
    return copy_file(src, dest)
  }
  if !path_is_dir(src) {
    return Err(
      CliError::CommandError(
        "Failed to copy " +
        src +
        " to " +
        dest +
        ": source path is not a file or directory",
      ),
    )
  }
  if !path_exists(dest) {
    @async_fs.mkdir(dest, recursive=true) catch {
      err =>
        return Err(
          CliError::CommandError(
            "Failed to create " +
            dest +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  }
  let entries = @async_fs.readdir(
    src,
    include_hidden=true,
    include_special=false,
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to read " + src + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  for entry in entries {
    let child_src = path_join(src, entry)
    let child_dest = path_join(dest, entry)
    match copy_tree(child_src, child_dest) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn ensure_dir(path : String) -> Result[Unit, CliError] {
  guard !path_exists(path) else { return Ok(()) }
  @async_fs.mkdir(path, recursive=true) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to create " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn normalize_cef_runtime_layout(root : String) -> Result[Unit, CliError] {
  let release_dir = path_join(root, "Release")
  if !path_exists(release_dir) {
    @mbfs.create_dir(release_dir) catch {
      err =>
        return Err(
          CliError::CommandError(
            "Failed to create Release directory: " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  }
  for
    file_name in [
      "icudtl.dat", "chrome_100_percent.pak", "chrome_200_percent.pak", "resources.pak",
    ] {
    match
      copy_file_if_exists(
        path_join(path_join(root, "Resources"), file_name),
        path_join(release_dir, file_name),
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn find_project_root_from(start : String) -> String {
  for dir = start; dir != ""; {
    if path_exists(path_join(dir, "moon.work")) ||
      path_exists(path_join(dir, "moon.mod")) {
      return dir
    }
    let parent = path_parent(dir)
    if parent == dir {
      return start
    }
    continue parent
  }
  start
}

///|
fn project_root(cwd : String) -> Result[String, CliError] {
  if cwd != "" && cwd != "." {
    return Ok(find_project_root_from(cwd))
  }
  match @env.current_dir() {
    Some(cwd) => Ok(find_project_root_from(cwd))
    None => Err(CliError::CommandError("Failed to read current directory"))
  }
}

///|
fn archive_url(name : String, url : String?) -> String {
  match url {
    Some(url) => url
    None => default_cef_base_url + "/" + name + ".tar.bz2"
  }
}

///|
fn find_prebuilt_root(
  root : String,
  platform : String,
) -> Result[String, CliError] {
  let package_prebuilt = path_join(
    path_join(path_join(root, "proton"), "prebuilt"),
    platform,
  )
  if all_exist(package_prebuilt, proton_prebuilt_relative_files()) {
    return Ok(package_prebuilt)
  }
  let mooncakes_prebuilt = path_join(
    path_join(path_join(path_join(root, ".mooncakes"), "justjavac"), "proton"),
    path_join("prebuilt", platform),
  )
  if all_exist(mooncakes_prebuilt, proton_prebuilt_relative_files()) {
    return Ok(mooncakes_prebuilt)
  }
  let dev_dist = path_join(path_join(root, "native"), "dist")
  if all_exist(dev_dist, proton_prebuilt_relative_files()) {
    return Ok(dev_dist)
  }
  Err(
    CliError::CommandError(
      "Missing Proton prebuilt artifacts for " +
      platform +
      ". Expected " +
      package_prebuilt +
      ", " +
      mooncakes_prebuilt +
      " or " +
      dev_dist,
    ),
  )
}

///|
fn require_windows() -> Result[Unit, CliError] {
  if @path.sep == '\\' {
    Ok(())
  } else {
    Err(
      CliError::CommandError(
        "The Proton CEF backend is currently Windows-only.",
      ),
    )
  }
}

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
async fn make_temp_dir() -> Result[String, CliError] {
  let temp_dir = @async_fs.tmpdir(prefix="proton-cef-") catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to create temp directory: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  if temp_dir == "" {
    Err(CliError::CommandError("Failed to create temp directory"))
  } else {
    Ok(temp_dir)
  }
}

///|
async fn download_file(
  url : String,
  destination : String,
) -> Result[Unit, CliError] {
  println("[INFO] Downloading CEF: " + url)
  let code = @process.run("curl", ["-L", "--fail", "--output", destination, url]) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Download failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CliError::CommandError(
        "Download failed: curl exited with code " + code.to_string(),
      ),
    )
  }
  Ok(())
}

///|
async fn extract_tar_bz2(
  archive_path : String,
  destination : String,
) -> Result[Unit, CliError] {
  println("[INFO] Extracting: " + archive_path)
  let code = @process.run("tar", ["-xjf", archive_path, "-C", destination]) catch {
    err =>
      return Err(
        CliError::CommandError(
          "tar failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CliError::CommandError(
        "tar failed: tar exited with code " + code.to_string(),
      ),
    )
  }
  Ok(())
}

///|
fn find_extracted_root(
  extract_dir : String,
  name : String,
) -> Result[String, CliError] {
  let named = path_join(extract_dir, name)
  if has_source_cef_files(named) {
    return Ok(named)
  }
  let candidates : Array[String] = []
  let entries = @mbfs.read_dir(extract_dir) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to read extract directory: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  for entry in entries {
    guard entry.has_prefix("cef_binary_") else { continue }
    let candidate = path_join(extract_dir, entry)
    if path_is_dir(candidate) && has_source_cef_files(candidate) {
      candidates.push(candidate)
    }
  }
  match candidates {
    [candidate] => Ok(candidate)
    _ =>
      Err(
        CliError::CommandError(
          "Could not find extracted CEF root in " + extract_dir,
        ),
      )
  }
}

///|
fn assert_safe_install_dir(
  install_dir : String,
  root : String,
) -> Result[Unit, CliError] {
  let normalized_install = install_dir.replace(old="/", new="\\")
  let normalized_root = root.replace(old="/", new="\\")
  let parent = path_parent(normalized_root)
  if normalized_install == "" ||
    normalized_install.has_suffix(":\\") ||
    normalized_install == normalized_root ||
    normalized_install == parent {
    Err(
      CliError::CommandError(
        "Refusing to replace unsafe CEF install directory: " + install_dir,
      ),
    )
  } else {
    Ok(())
  }
}

///|
async fn remove_tree(path : String) -> Result[Unit, CliError] {
  guard path_exists(path) else { return Ok(()) }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      err =>
        return Err(
          CliError::CommandError(
            "Failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  } else if path_is_dir(path) {
    @async_fs.rmdir(path, recursive=true) catch {
      err =>
        return Err(
          CliError::CommandError(
            "Failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  } else {
    return Err(
      CliError::CommandError(
        "Failed to remove " + path + ": path is not a file or directory",
      ),
    )
  }
  Ok(())
}

///|
async fn install_cef_root(
  extracted_root : String,
  install_dir : String,
  name : String,
  root : String,
) -> Result[Unit, CliError] {
  match assert_safe_install_dir(install_dir, root) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match remove_tree(install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  println("[INFO] Installing CEF into: " + install_dir)
  match copy_tree(extracted_root, install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match normalize_cef_runtime_layout(install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  @mbfs.write_string_to_file(
    path_join(install_dir, "version.txt"),
    name + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to write CEF version: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn ensure_cef_cache(
  name : String,
  url : String?,
  root : String,
  cache_dir : String,
) -> Result[Unit, CliError] {
  if installed_version(cache_dir) == name {
    return normalize_cef_runtime_layout(cache_dir)
  }
  let legacy_cache = path_join(root, ".cef-cache")
  if installed_version(legacy_cache) == name {
    return install_cef_root(legacy_cache, cache_dir, name, root)
  }
  setup_downloaded_cef(name, url, root, cache_dir)
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
fn runtime_manifest_json(
  platform : String,
  cef_name : String,
  dist : String,
) -> String {
  Json::object({
    "platform": Json::string(platform),
    "proton_version": Json::string(proton_version),
    "cef_version": Json::string(cef_name),
    "dist": Json::string(dist),
  }).stringify()
}

///|
fn write_runtime_metadata(
  root : String,
  runtime_dir : String,
  platform : String,
  cef_name : String,
  relative_dist : String,
) -> Result[Unit, CliError] {
  let manifest = runtime_manifest_json(platform, cef_name, relative_dist)
  @mbfs.write_string_to_file(
    path_join(runtime_dir, "manifest.json"),
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to write runtime manifest: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @mbfs.write_string_to_file(
    path_join(path_join(root, ".proton"), "runtime.json"),
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to write active runtime manifest: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @mbfs.write_string_to_file(
    path_join(runtime_dir, "version.txt"),
    "proton=" + proton_version + "\ncef=" + cef_name + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to write runtime version: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn assemble_runtime(
  root : String,
  platform : String,
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
    write_runtime_metadata(root, runtime_dir, platform, cef_name, relative_dist) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  validate_runtime_dist(runtime_dir)
}

///|
async fn setup_downloaded_cef(
  name : String,
  url : String?,
  root : String,
  install_dir : String,
) -> Result[Unit, CliError] {
  let temp_dir = match make_temp_dir() {
    Ok(temp_dir) => temp_dir
    Err(error) => return Err(error)
  }
  let archive_path = path_join(temp_dir, name + ".tar.bz2")
  let setup_result = match download_file(archive_url(name, url), archive_path) {
    Err(error) => Err(error)
    Ok(_) =>
      match extract_tar_bz2(archive_path, temp_dir) {
        Err(error) => Err(error)
        Ok(_) =>
          match find_extracted_root(temp_dir, name) {
            Err(error) => Err(error)
            Ok(extracted_root) =>
              install_cef_root(extracted_root, install_dir, name, root)
          }
      }
  }
  let cleanup_result = remove_tree(temp_dir)
  match setup_result {
    Err(error) => {
      ignore(cleanup_result)
      Err(error)
    }
    Ok(_) => cleanup_result
  }
}

///|
fn installed_version(install_dir : String) -> String {
  let version_path = path_join(install_dir, "version.txt")
  if path_is_file(version_path) {
    @mbfs.read_file_to_string(version_path, encoding="utf8").trim().to_owned() catch {
      _ => ""
    }
  } else {
    ""
  }
}

///|
async fn run_cef_setup(
  cwd : String,
  args : Array[String],
) -> Result[Unit, CliError] {
  let cmd = cef_setup_arg_parser()
  let matches = cmd.parse(argv=args, env={}) catch {
    err => return Err(CliError::UsageError(err.to_string(), true))
  }
  match require_windows() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = match match_value(matches, "name") {
    Some(name) => name
    None => default_cef_name
  }
  let url = match_value(matches, "url")
  let root = match project_root(cwd) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  let platform = platform_id()
  let proton_root = path_join(root, ".proton")
  let cache_dir = path_join(
    path_join(path_join(path_join(proton_root, "cache"), "cef"), platform),
    name,
  )
  let relative_dist = relative_runtime_dist(platform, name)
  let runtime_dir = path_join(root, relative_dist)
  let prebuilt_root = match find_prebuilt_root(root, platform) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  match ensure_cef_cache(name, url, root, cache_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_cef_root(cache_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    assemble_runtime(
      root, platform, name, cache_dir, prebuilt_root, runtime_dir, relative_dist,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  println(runtime_dir)
  Ok(())
}
