///|
test "the AppDir keeps Proton resources at the shared runtime location" {
  assert_eq(linux_package_rpath, "$ORIGIN/../Resources/proton/bin")
}

///|
test "packages strip only the runtime's shared libraries" {
  assert_eq(
    linux_shared_libraries([
      "chrome-sandbox", "icudtl.dat", "libEGL.so", "libcef.so", "libvulkan.so.1",
      "locales", "v8_context_snapshot.bin",
    ]),
    ["libEGL.so", "libcef.so", "libvulkan.so.1"],
  )
}

///|
test "the AppImage launcher establishes the CEF loader environment" {
  inspect(
    proton_linux_apprun("demo"),
    content=(
      #|#!/bin/sh
      #|PREFIX="$APPDIR/usr"
      #|PROTON_ROOT="$PREFIX/Resources/proton"
      #|CEF_LIBRARY="$PROTON_ROOT/bin/libcef.so"
      #|export PROTON_RUNTIME_ROOT="$PROTON_ROOT"
      #|export PROTON_HELPER_PATH="$PREFIX/bin/cef_process"
      #|export LD_LIBRARY_PATH="$PROTON_ROOT/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      #|export LD_PRELOAD="$CEF_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
      #|exec "$PREFIX/bin/demo" "$@"
      #|
    ),
  )
}

///|
test "the prefix launcher locates the package from its own path" {
  let script = proton_linux_launcher("demo")
  assert_true(
    script.has_prefix(
      "#!/bin/sh\nPREFIX=\"$(dirname \"$(dirname \"$(readlink -f \"$0\")\")\")\"\n",
    ),
  )
  assert_eq(
    script.replace(
      old="PREFIX=\"$(dirname \"$(dirname \"$(readlink -f \"$0\")\")\")\"",
      new="PREFIX=\"$APPDIR/usr\"",
    ),
    proton_linux_apprun("demo"),
  )
}
