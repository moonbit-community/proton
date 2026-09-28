///|
test "flatpak is a Linux package format" {
  assert_eq(PackageFormat::parse("Flatpak"), Flatpak)
  assert_eq(PackageFormat::Flatpak.to_string(), "flatpak")
  assert_eq(resolve_package_formats_for_host([AppImage, Flatpak], Linux), [
    AppImage,
    Flatpak,
  ])
  try ignore(resolve_package_formats_for_host([Flatpak], Macos)) catch {
    UnsupportedFormatForPlatform(format~, ..) => assert_eq(format, "flatpak")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected flatpak to be rejected on macOS")
  }
}

///|
test "flatpak application IDs follow Flatpak naming rules" {
  validate_flatpak_app_id("dev.proton.demo")
  validate_flatpak_app_id("org._example.demo-app")
  for
    invalid in [
      "dev.demo", "dev.proton-app.demo", "dev.1proton.demo", "dev.proton.de mo",
      "dev..demo",
    ] {
    try validate_flatpak_app_id(invalid) catch {
      InvalidConfiguration(..) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("expected \{invalid} to be rejected")
    }
  }
}

///|
test "flatpak metadata exports the application under its identifier" {
  let spec = package_test_spec([Flatpak])
  inspect(
    linux_desktop_entry(
      spec,
      exec="demo-app-launcher",
      icon=spec.identifier,
      appimage=false,
    ),
    content=(
      #|[Desktop Entry]
      #|Type=Application
      #|Terminal=false
      #|Categories=Utility;
      #|Name=Demo App
      #|Exec=demo-app-launcher %U
      #|Icon=dev.proton.demo
      #|MimeType=x-scheme-handler/devtoys;
      #|
    ),
  )
  inspect(
    flatpak_metadata(spec, "x86_64"),
    content=(
      #|[Application]
      #|name=dev.proton.demo
      #|runtime=org.freedesktop.Platform/x86_64/25.08
      #|sdk=org.freedesktop.Sdk/x86_64/25.08
      #|
    ),
  )
  debug_inspect(
    flatpak_finish_args(spec, "demo-app-launcher"),
    content=(
      #|[
      #|  "--command=demo-app-launcher",
      #|  "--share=ipc",
      #|  "--socket=x11",
      #|  "--device=dri",
      #|  "--share=network",
      #|  "--socket=pulseaudio",
      #|  "--env=CHROME_DESKTOP=dev.proton.demo.desktop",
      #|]
    ),
  )
  let metainfo = flatpak_metainfo(PackageSpec::{
    ..spec,
    product_name: "Demo & <App>",
  })
  assert_true(metainfo.contains("<id>dev.proton.demo</id>"))
  assert_true(metainfo.contains("<name>Demo &amp; &lt;App&gt;</name>"))
  assert_true(
    metainfo.contains(
      "<launchable type=\"desktop-id\">dev.proton.demo.desktop</launchable>",
    ),
  )
  assert_true(metainfo.contains("<release version=\"1.2.3\"/>"))
}

///|
test "flatpak icons are placed by their square PNG size" {
  let header = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR"
  let png = size => {
    let buffer = @buffer.Buffer()
    buffer.write_bytes(header)
    buffer.write_uint_be(size)
    buffer.write_uint_be(size)
    buffer.to_bytes()
  }
  assert_eq(png_icon_size(png(256U)), 256)
  let wide = @buffer.Buffer()
  wide.write_bytes(header)
  wide.write_uint_be(256)
  wide.write_uint_be(128)
  for invalid in [b"not a png", wide.to_bytes()] {
    try ignore(png_icon_size(invalid)) catch {
      InvalidConfiguration(..) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("expected the icon to be rejected")
    }
  }
}
