///|
/// Mach-O file types that carry loadable code: MH_EXECUTE, MH_DYLIB and
/// MH_BUNDLE. Object files are compiler and linker inputs and take no signature.
fn macho_filetype_is_code(filetype : UInt32) -> Bool {
  filetype is (2 | 6 | 8)
}

///|
fn macho_u32(data : Bytes, offset : Int32, little_endian~ : Bool) -> UInt32 {
  let bytes = [
    data[offset].to_uint(),
    data[offset + 1].to_uint(),
    data[offset + 2].to_uint(),
    data[offset + 3].to_uint(),
  ]
  if little_endian {
    bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
  } else {
    (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
  }
}

///|
fn macho_u64(data : Bytes, offset : Int32, little_endian~ : Bool) -> Int64 {
  let first = macho_u32(data, offset, little_endian~).to_uint64()
  let second = macho_u32(data, offset + 4, little_endian~).to_uint64()
  let value = if little_endian {
    first | (second << 32)
  } else {
    (first << 32) | second
  }
  value.reinterpret_as_int64()
}

///|
fn macho_thin_is_code(header : Bytes) -> Bool {
  guard header.length() >= 16 else { return false }
  match macho_u32(header, 0, little_endian=false) {
    0xcffaedfeU | 0xcefaedfeU =>
      macho_filetype_is_code(macho_u32(header, 12, little_endian=true))
    0xfeedfacfU | 0xfeedfaceU =>
      macho_filetype_is_code(macho_u32(header, 12, little_endian=false))
    _ => false
  }
}

///|
/// Reads what exists of the range, so a header or slice table that runs past
/// the end of the file (a Java class file shares the universal magic) comes
/// back short instead of failing the scan.
async fn macho_read(
  file : @async_fs.File,
  position : Int64,
  length : Int64,
) -> Bytes {
  let available = file.size() - position
  guard position >= 0 && available > 0 else { return b"" }
  file.at(position).read_exactly(@cmp.minimum(length, available).to_int())
}

///|
/// Whether a file is Mach-O code. A universal file counts when any slice does.
async fn macho_file_is_code(path : String) -> Bool {
  let file = @async_fs.open(path, mode=ReadOnly)
  defer file.close()
  let header = macho_read(file, 0, 16)
  guard header.length() >= 8 else { return false }
  let (little_endian, fat64) = match macho_u32(header, 0, little_endian=false) {
    0xcafebabeU => (false, false)
    0xbebafecaU => (true, false)
    0xcafebabfU => (false, true)
    0xbfbafecaU => (true, true)
    _ => return macho_thin_is_code(header)
  }
  let count = macho_u32(header, 4, little_endian~).to_int64()
  let entry_size = if fat64 { 32 } else { 20 }
  let entries = macho_read(file, 8, count * entry_size.to_int64())
  for entry = 0
      entry + entry_size <= entries.length()
      entry = entry + entry_size {
    let offset = if fat64 {
      macho_u64(entries, entry + 8, little_endian~)
    } else {
      macho_u32(entries, entry + 8, little_endian~).to_int64()
    }
    if macho_thin_is_code(macho_read(file, offset, 16)) {
      return true
    }
  }
  false
}

///|
/// A bundle's name without its extension, which CFBundle and `codesign` take
/// as the executable name when the bundle does not declare one.
fn bundle_stem(bundle : String) -> String {
  let name = host_path(bundle).basename()
  let stem = if name.rev_find(".") is Some(dot) { name[:dot] } else { name }
  stem.to_owned()
}

///|
/// The executable name a bundle's `Info.plist` declares, or the bundle's stem
/// when the plist lacks `CFBundleExecutable`.
async fn bundle_executable_name(
  info_plist : String,
  bundle~ : String,
) -> String? {
  guard path_is_file(info_plist) else { return None }
  let output = @process.run(
    "/usr/bin/plutil",
    ["-extract", "CFBundleExecutable", "raw", "-o", "-", info_plist],
    stdout=Collect,
    stderr=DuplicateStdout,
  )
  let code = output.exit_code
  guard code == 0 else { return Some(bundle_stem(bundle)) }
  let text = output.stdout_text() catch { _ => return None }
  // `plutil` ends raw output with a newline; the name itself stays exact.
  let name = text.strip_suffix("\n").unwrap_or(text).to_owned()
  if name == "" || name.contains("/") {
    None
  } else {
    Some(name)
  }
}

///|
/// The main executable paths of a code bundle, or `None` for a directory that
/// is not one. A bundle is recognized by its structure, not its suffix: an
/// `Info.plist` naming a `CFBundleExecutable` that exists, in `Contents/MacOS`
/// for apps and plug-ins, or at the root of a framework, a framework version or
/// a shallow bundle. A `.framework` needs no `Info.plist`: `codesign` signs it
/// by its stem.
/// A framework's other versions are included because symlinks such as
/// `Versions/Current` are not scanned, so only real paths are compared.
async fn bundle_main_executables(directory : String) -> Array[String]? {
  let contents = path_join(directory, "Contents")
  if bundle_executable_name(path_join(contents, "Info.plist"), bundle=directory)
    is Some(name) {
    let main = path_join(path_join(contents, "MacOS"), name)
    return if path_exists(main) { Some([main]) } else { None }
  }
  let name = match
    bundle_executable_name(
      path_join(directory, "Resources/Info.plist"),
      bundle=directory,
    ) {
    Some(name) => name
    None =>
      match
        bundle_executable_name(
          path_join(directory, "Info.plist"),
          bundle=directory,
        ) {
        Some(name) => name
        None =>
          if directory.has_suffix(".framework") {
            bundle_stem(directory)
          } else {
            return None
          }
      }
  }
  let main = path_join(directory, name)
  guard path_exists(main) else { return None }
  let paths = [main]
  let versions = path_join(directory, "Versions")
  if path_is_dir(versions) {
    for version in @async_fs.readdir(versions, include_hidden=true) {
      paths.push(path_join(path_join(versions, version), name))
    }
  }
  Some(paths)
}

///|
/// Appends the code under `directory` to `ordered` in signing order. Signing a
/// bundle's main executable or the bundle itself seals the bundle over the code
/// it contains, so each bundle's contents come first, then its main
/// executables, which collect in `deferred` while plain subdirectories are
/// walked, and then the bundle directory.
async fn collect_macos_code(
  directory : String,
  main_executables : Array[String],
  ordered : Array[String],
  deferred : Array[String],
) -> Unit {
  for name in @async_fs.readdir(directory, include_hidden=true, sort=true) {
    let path = path_join(directory, name)
    // Symlinks are skipped: a framework's `Versions/Current` aliases code that
    // is reached through its real path.
    match @async_fs.kind(path, follow_symlink=false) {
      Directory =>
        if bundle_main_executables(path) is Some(mains) {
          let bundle_deferred = []
          collect_macos_code(path, mains, ordered, bundle_deferred)
          ordered.append(bundle_deferred)
          ordered.push(path)
        } else {
          collect_macos_code(path, main_executables, ordered, deferred)
        }
      Regular =>
        if macho_file_is_code(path) {
          if main_executables.contains(path) {
            deferred.push(path)
          } else {
            ordered.push(path)
          }
        }
      _ => ()
    }
  }
}

///|
/// The code objects under `root` in signing order: every Mach-O with loadable
/// code, plus each nested code bundle after its contents. The main executables
/// of the bundles that contain or are `root` come last, so a tree such as
/// `Tool.app/Contents/MacOS` keeps the enclosing bundle's seal valid, followed
/// by `root` itself when it is a bundle: signing a framework's executable does
/// not reseal the framework.
async fn macos_tree_sign_paths(root : String) -> Array[String] {
  let main_executables = []
  let root_is_bundle = bundle_main_executables(root) is Some(_)
  for directory = root {
    if bundle_main_executables(directory) is Some(mains) {
      main_executables.append(mains)
    }
    let parent = path_parent(directory)
    if parent == directory {
      break
    }
    continue parent
  }
  let ordered = []
  let deferred = []
  collect_macos_code(root, main_executables, ordered, deferred)
  ordered.append(deferred)
  if root_is_bundle {
    ordered.push(root)
  }
  ordered
}
