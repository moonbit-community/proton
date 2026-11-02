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
  file.read_exactly_at(@cmp.minimum(length, available).to_int(), position~)
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
async fn collect_macos_code(directory : String, found : Array[String]) -> Unit {
  for name in @async_fs.readdir(directory, include_hidden=true) {
    let path = path_join(directory, name)
    // Symlinks are skipped: a framework's `Versions/Current` aliases code that
    // is reached through its real path.
    match @async_fs.kind(path, follow_symlink=false) {
      Directory => {
        collect_macos_code(path, found)
        if path.has_suffix(".app") ||
          path.has_suffix(".framework") ||
          path.has_suffix(".xpc") {
          found.push(path)
        }
      }
      Regular => if macho_file_is_code(path) { found.push(path) }
      _ => ()
    }
  }
}

///|
/// Higher ranks sign first. A deeper path is signed before the bundle that
/// contains it, because a bundle's seal covers its nested code. Signing an app's
/// main executable seals the app, so `Contents/MacOS` waits for the code beside
/// it at the same depth.
fn macos_sign_rank(path : String) -> Int32 {
  let main_executable = path_parent(path).has_suffix(".app/Contents/MacOS")
  path.split("/").count() * 2 + (if main_executable { 0 } else { 1 })
}

///|
/// The code objects under `root` in signing order: every Mach-O with loadable
/// code, plus each nested app, framework and XPC service after its contents.
async fn macos_tree_sign_paths(root : String) -> Array[String] {
  let found = []
  collect_macos_code(root, found)
  found.sort_by((left, right) => {
    match macos_sign_rank(right).compare(macos_sign_rank(left)) {
      0 => left.compare(right)
      order => order
    }
  })
  found
}
