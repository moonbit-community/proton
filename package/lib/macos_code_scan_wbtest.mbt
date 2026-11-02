///|
fn macho_header(
  magic : UInt32,
  filetype : UInt32,
  little_endian~ : Bool,
) -> Bytes {
  let bytes = Array::make(16, b'\x00')
  let write = (offset : Int32, value : UInt32) => {
    for index in 0..<4 {
      let shift = if little_endian { index * 8 } else { (3 - index) * 8 }
      bytes[offset + index] = ((value >> shift) & 0xff).to_byte()
    }
  }
  write(0, magic)
  write(12, filetype)
  Bytes::from_array(bytes)
}

///|
const MachoMagic64 : UInt32 = 0xfeedfacf

///|
fn thin_library() -> Bytes {
  macho_header(MachoMagic64, 6, little_endian=true)
}

///|
fn thin_object() -> Bytes {
  macho_header(MachoMagic64, 1, little_endian=true)
}

///|
fn universal(
  slices : Array[Bytes],
  fat64~ : Bool,
  little_endian~ : Bool,
) -> Bytes {
  let entry_size = if fat64 { 32 } else { 20 }
  let header_size = 8 + slices.length() * entry_size
  let bytes = Array::make(header_size + slices.length() * 16, b'\x00')
  let write32 = (offset : Int32, value : UInt32) => {
    for index in 0..<4 {
      let shift = if little_endian { index * 8 } else { (3 - index) * 8 }
      bytes[offset + index] = ((value >> shift) & 0xff).to_byte()
    }
  }
  write32(0, if fat64 { 0xcafebabfU } else { 0xcafebabeU })
  write32(4, slices.length().reinterpret_as_uint())
  for index, slice in slices {
    let position = header_size + index * 16
    let entry = 8 + index * entry_size
    if fat64 {
      write32(
        entry + (if little_endian { 8 } else { 12 }),
        position.reinterpret_as_uint(),
      )
    } else {
      write32(entry + 8, position.reinterpret_as_uint())
    }
    for offset, byte in slice {
      bytes[position + offset] = byte
    }
  }
  Bytes::from_array(bytes)
}

///|
async fn write_fixture(root : String, path : String, bytes : Bytes) -> Unit {
  let file = path_join(root, path)
  @async_fs.mkdir(path_parent(file), recursive=true, allow_exist=true)
  @async_fs.write_file(file, bytes, create_mode=CreateOrTruncate)
}

///|
async fn with_scan_root(body : async (String) -> Unit) -> Unit {
  let root = @async_fs.tmpdir(prefix="proton-code-scan-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  body(root)
}

///|
fn relative_paths(root : String, paths : Array[String]) -> Array[String] {
  paths.map(path => {
    path.unsafe_substring(start=root.length() + 1, end=path.length())
  })
}

///|
async test "signing scan finds executables, libraries and bundles only" {
  // The scan only runs while signing on macOS, where paths use `/`.
  guard current_package_host() is Macos else { return }
  with_scan_root(async fn(root) {
    write_fixture(
      root,
      "bin/big-endian",
      macho_header(MachoMagic64, 2, little_endian=false),
    )
    write_fixture(
      root,
      "bin/thin-32",
      macho_header(0xfeedface, 2, little_endian=true),
    )
    write_fixture(root, "lib/.hidden", thin_library())
    write_fixture(
      root,
      "lib/plugin.cmxs",
      macho_header(MachoMagic64, 8, little_endian=true),
    )
    write_fixture(root, "lib/runtime.o", thin_object())
    write_fixture(root, "doc/readme.md", b"Bundled documentation\n")
    write_fixture(root, "empty", b"")
    let found = relative_paths(root, macos_tree_sign_paths(root))
    assert_eq(found.length(), 4)
    for
      path in [
        "bin/big-endian", "bin/thin-32", "lib/.hidden", "lib/plugin.cmxs",
      ] {
      assert_true(found.contains(path))
    }
  })
}

///|
async test "universal files count when any slice is code" {
  with_scan_root(async fn(root) {
    for fat64 in [false, true] {
      for little_endian in [false, true] {
        let name = "\{fat64}-\{little_endian}"
        write_fixture(
          root,
          "plugin-\{name}.cmxs",
          universal([thin_object(), thin_library()], fat64~, little_endian~),
        )
        write_fixture(
          root,
          "runtime-\{name}.o",
          universal([thin_object(), thin_object()], fat64~, little_endian~),
        )
      }
    }
    let found = relative_paths(root, macos_tree_sign_paths(root))
    assert_eq(found.length(), 4)
    assert_true(found.all(path => path.has_prefix("plugin-")))
  })
}

///|
async test "a slice table past the end of the file is not code" {
  with_scan_root(async fn(root) {
    // A Java class file: the universal magic, then a version number.
    write_fixture(
      root, "Example.class", b"\xca\xfe\xba\xbe\x00\x00\x00\x34\x00\x10",
    )
    write_fixture(root, "short", b"\xca\xfe\xba\xbe\xff\xff\xff\xff")
    assert_eq(macos_tree_sign_paths(root), [])
  })
}

///|
async test "signing scan does not follow symlinks" {
  // The scan only runs while signing on macOS, where paths use `/`.
  guard current_package_host() is Macos else { return }
  with_scan_root(async fn(root) {
    write_fixture(root, "real/libfoo.dylib", thin_library())
    @async_fs.symlink(target="real", path_join(root, "alias"))
    @async_fs.symlink(target="real/libfoo.dylib", path_join(root, "link.dylib"))
    assert_eq(relative_paths(root, macos_tree_sign_paths(root)), [
      "real/libfoo.dylib",
    ])
  })
}

///|
async test "signing scan orders nested bundles inside-out" {
  // The scan only runs while signing on macOS, where paths use `/`.
  guard current_package_host() is Macos else { return }
  with_scan_root(async fn(root) {
    let library = thin_library()
    write_fixture(root, "tool", library)
    write_fixture(
      root, "Nested.app/Contents/Info.plist", b"<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>A-main</string></dict></plist>",
    )
    // The main executable sorts first by name, so the scan has to defer it.
    write_fixture(root, "Nested.app/Contents/MacOS/A-main", library)
    write_fixture(root, "Nested.app/Contents/MacOS/Z-helper", library)
    write_fixture(root, "Nested.app/Contents/Helpers/helper", library)
    write_fixture(
      root, "Nested.app/Contents/Frameworks/Foo.framework/Versions/A/Libraries/libx.dylib",
      library,
    )
    write_fixture(
      root, "Nested.app/Contents/Frameworks/Foo.framework/Versions/A/Foo", library,
    )
    write_fixture(root, "Service.xpc/Contents/Info.plist", b"<plist/>")
    write_fixture(root, "Plugin.bundle/Contents/MacOS/plugin", library)
    let found = relative_paths(root, macos_tree_sign_paths(root))
    let position = (path : String) => found.search(path).unwrap_or(-1)
    let foo = "Nested.app/Contents/Frameworks/Foo.framework"
    assert_true(
      position(foo + "/Versions/A/Libraries/libx.dylib") <
      position(foo + "/Versions/A/Foo"),
    )
    assert_true(position(foo + "/Versions/A/Foo") < position(foo))
    for sibling in ["Contents/Helpers/helper", "Contents/MacOS/Z-helper"] {
      assert_true(
        position("Nested.app/" + sibling) <
        position("Nested.app/Contents/MacOS/A-main"),
      )
    }
    assert_true(
      position("Nested.app/Contents/MacOS/A-main") < position("Nested.app"),
    )
    assert_true(
      position("Plugin.bundle/Contents/MacOS/plugin") <
      position("Plugin.bundle"),
    )
    assert_true(found.contains("Service.xpc"))
    assert_true(found.contains("tool"))
  })
}

///|
async test "macOS packaging signs every code object in a resource tree" {
  guard current_package_host() is Macos else { return }
  let root = @async_fs.tmpdir(prefix="proton-package-sign-tree-")
  defer (remove_tree(root) catch { _ => () })
  let source = path_join(root, "main.c")
  @async_fs.write_file(source, "int main(void) { return 0; }")
  let executable = path_join(root, "main")
  assert_eq(@process.run("cc", [source, "-o", executable]), 0)
  let payload = path_join(root, "payload")
  let tool = path_join(payload, "bin/tool")
  ensure_dir(path_parent(tool))
  assert_eq(@process.run("cc", [source, "-o", tool]), 0)
  write_fixture(payload, "share/notes.txt", b"not code\n")
  let foo = path_join(payload, "lib/Foo.framework")
  let version = path_join(foo, "Versions/A")
  ensure_dir(path_join(version, "Libraries"))
  let library = path_join(root, "library.c")
  @async_fs.write_file(library, "int foo(void) { return 1; }")
  for output in ["Foo", "Libraries/libx.dylib"] {
    assert_eq(
      @process.run("cc", [
        "-dynamiclib",
        library,
        "-o",
        path_join(version, output),
      ]),
      0,
    )
  }
  write_fixture(
    version,
    "Resources/Info.plist",
    @utf8.encode(
      "<plist version=\"1.0\"><dict>" +
      "<key>CFBundleIdentifier</key><string>com.example.foo</string>" +
      "<key>CFBundleExecutable</key><string>Foo</string>" +
      "</dict></plist>",
    ),
  )
  @async_fs.symlink(target="A", path_join(foo, "Versions/Current"))
  // A plug-in whose main executable sorts before its sibling.
  let plugin = path_join(payload, "lib/Test.bundle/Contents")
  ensure_dir(path_join(plugin, "MacOS"))
  write_fixture(
    plugin,
    "Info.plist",
    @utf8.encode(
      "<plist version=\"1.0\"><dict>" +
      "<key>CFBundleIdentifier</key><string>com.example.plugin</string>" +
      "<key>CFBundleExecutable</key><string>A-plugin</string>" +
      "</dict></plist>",
    ),
  )
  assert_eq(
    @process.run("cc", [
      "-bundle",
      library,
      "-o",
      path_join(plugin, "MacOS/A-plugin"),
    ]),
    0,
  )
  assert_eq(
    @process.run("cc", [source, "-o", path_join(plugin, "MacOS/Z-helper")]),
    0,
  )
  @async_fs.symlink(target="Versions/Current/Foo", path_join(foo, "Foo"))
  @async_fs.symlink(
    target="Versions/Current/Resources",
    path_join(foo, "Resources"),
  )
  let spec = PackageSpec(
    executable,
    "Tree Test",
    "com.example.tree",
    "1.0.0",
    [App],
    path_join(root, "out"),
    payloads=[Payload(payload, "payload")],
  )
  let artifacts = build_with(
    spec,
    PackageCustomization(macos_sign_targets=[
      MacosSignTarget("Contents/Resources/payload", tree=true),
    ]),
    fn(_) {  },
  )
  let (_, details) = @process.collect_output_merged("/usr/bin/codesign", [
    "--display",
    "--verbose=2",
    path_join(artifacts[0], "Contents/Resources/payload/bin/tool"),
  ])
  assert_true(details.text().contains("flags=0x10002(adhoc,runtime)"))
  // Signing out of order leaves a bundle's seal invalid.
  for bundle in ["Foo.framework", "Test.bundle"] {
    assert_eq(
      @process.run("/usr/bin/codesign", [
        "--verify",
        "--deep",
        "--strict",
        path_join(artifacts[0], "Contents/Resources/payload/lib/" + bundle),
      ]),
      0,
    )
  }
}
