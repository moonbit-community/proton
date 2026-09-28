///|
/// The Freedesktop runtime already provides GTK 3, NSS, CUPS, ATK and the X11
/// libraries that a CEF-based application links against.
const FLATPAK_RUNTIME : String = "org.freedesktop.Platform"

///|
const FLATPAK_SDK : String = "org.freedesktop.Sdk"

///|
const FLATPAK_RUNTIME_VERSION : String = "25.08"

///|
/// Lets `flatpak install` of a bundle fetch the runtime it depends on.
const FLATPAK_RUNTIME_REPO : String = "https://dl.flathub.org/repo/flathub.flatpakrepo"

///|
const FLATPAK_BRANCH : String = "stable"

///|
/// Validates a Flatpak application ID, which is stricter than a reverse-DNS
/// bundle identifier: at least three components, no leading digits, and a
/// hyphen only in the last component.
fn validate_flatpak_app_id(value : String) -> Unit raise LinuxPackagingError {
  let invalid = reason => {
    LinuxPackagingError::InvalidConfiguration(
      detail="invalid Flatpak application ID " + value + ": " + reason,
    )
  }
  guard value.length() <= 255 else { raise invalid("longer than 255 bytes") }
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 3 else {
    raise invalid("expected at least three components")
  }
  for index, component in components {
    guard component is [first, ..] &&
      (first.is_ascii_alphabetic() || first == '_') else {
      raise invalid("a component must start with an ASCII letter or underscore")
    }
    for char in component {
      if char == '-' && index != components.length() - 1 {
        raise invalid("only the last component may contain a hyphen")
      }
      guard char.is_ascii_alphabetic() ||
        char.is_ascii_digit() ||
        char == '_' ||
        char == '-' else {
        raise invalid("contains an unsupported character")
      }
    }
  }
}

///|
/// Sandbox permissions for the baseline Proton window host. The engine embeds
/// CEF into GTK on X11 only, so the X11 socket is required rather than a
/// Wayland fallback.
fn flatpak_finish_args(spec : PackageSpec, command : String) -> Array[String] {
  [
    "--command=" + command,
    "--share=ipc",
    "--socket=x11",
    "--device=dri",
    "--share=network",
    "--socket=pulseaudio",
    "--env=CHROME_DESKTOP=" + linux_desktop_name(spec),
  ]
}

///|
fn flatpak_metadata(spec : PackageSpec, arch : String) -> String {
  let runtime_suffix = "/" + arch + "/" + FLATPAK_RUNTIME_VERSION
  "[Application]\nname=" +
  spec.identifier +
  "\nruntime=" +
  FLATPAK_RUNTIME +
  runtime_suffix +
  "\nsdk=" +
  FLATPAK_SDK +
  runtime_suffix +
  "\n"
}

///|
fn flatpak_metainfo(spec : PackageSpec) -> String {
  let id = xml_escape(spec.identifier)
  let name = xml_escape(spec.product_name)
  (
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<component type="desktop-application">
    $|  <id>\{id}</id>
    $|  <name>\{name}</name>
    $|  <summary>\{name}</summary>
    $|  <metadata_license>CC0-1.0</metadata_license>
    $|  <launchable type="desktop-id">\{id}.desktop</launchable>
    $|  <releases>
    $|    <release version="\{xml_escape(spec.version)}"/>
    $|  </releases>
    $|</component>
    $|
  )
}

///|
/// Returns the square pixel size of a PNG icon, which selects its hicolor
/// theme directory. Flatpak rejects exported icons larger than that directory.
fn png_icon_size(data : Bytes) -> Int raise LinuxPackagingError {
  guard data
    is [
      0x89,
      b'P',
      b'N',
      b'G',
      b'\r',
      b'\n',
      0x1A,
      b'\n',
      _,
      _,
      _,
      _,
      b'I',
      b'H',
      b'D',
      b'R',
      u32be(width),
      u32be(height),
      ..,
    ] else {
    raise LinuxPackagingError::InvalidConfiguration(
      detail="the flatpak format requires a valid PNG icon",
    )
  }
  guard width == height && width > 0U else {
    raise LinuxPackagingError::InvalidConfiguration(
      detail="the flatpak format requires a square PNG icon",
    )
  }
  width.reinterpret_as_int()
}

///|
/// Builds a single-file Flatpak bundle whose `/app` is the staged `usr`
/// prefix. The bundle names Flathub as its runtime source so installing it
/// on a machine without the Freedesktop runtime still succeeds.
async fn create_flatpak(
  spec : PackageSpec,
  prefix : String,
  icon : String,
  command : String,
  arch : String,
) -> String {
  let name = executable_name(spec.product_name)
  let icon_data = @async_fs.read_file(icon).binary() catch {
    error =>
      raise PackageFileSystemError::Read(
        path=icon,
        detail=@debug.render(Repr(error)),
      )
  }
  let icon_size = png_icon_size(icon_data).to_string()
  let build = path_join(spec.output, "." + name + ".flatpak-build")
  let repo = path_join(spec.output, "." + name + ".flatpak-repo")
  let destination = path_join(
    spec.output,
    name + "-" + spec.version + "-" + arch + ".flatpak",
  )
  let staging = destination + ".staging"
  for path in [build, repo, staging] {
    remove_tree(path)
  }
  defer (for path in [build, repo] {
    remove_tree(path) catch {
      _ => ()
    }
  })
  errdefer (remove_tree(staging) catch { _ => () })
  let files = path_join(build, "files")
  copy_tree(prefix, files)
  let share = path_join(files, "share")
  write_text(
    path_join(share, "applications/" + linux_desktop_name(spec)),
    linux_desktop_entry(
      spec,
      exec=command,
      icon=spec.identifier,
      appimage=false,
    ),
  )
  copy_file(
    icon,
    path_join(
      share,
      "icons/hicolor/" +
      icon_size +
      "x" +
      icon_size +
      "/apps/" +
      spec.identifier +
      ".png",
    ),
  )
  write_text(
    path_join(share, "metainfo/" + spec.identifier + ".metainfo.xml"),
    flatpak_metainfo(spec),
  )
  write_text(path_join(build, "metadata"), flatpak_metadata(spec, arch))
  run_linux_tool(
    "finish Flatpak",
    "flatpak",
    ["build-finish", build, ..flatpak_finish_args(spec, command)],
  )
  run_linux_tool("export Flatpak", "flatpak", [
    "build-export",
    "--arch=" + arch,
    repo,
    build,
    FLATPAK_BRANCH,
  ])
  run_linux_tool("bundle Flatpak", "flatpak", [
    "build-bundle",
    "--arch=" + arch,
    "--runtime-repo=" + FLATPAK_RUNTIME_REPO,
    repo,
    staging,
    spec.identifier,
    FLATPAK_BRANCH,
  ])
  promote(staging, destination)
  destination
}
