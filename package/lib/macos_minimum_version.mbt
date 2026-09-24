///|
/// Read the deployment version, not the build SDK, from each architecture.
fn macos_load_command_minimum(output : String) -> Int raise {
  let mut command = ""
  let mut minimum = 0
  for line in output.split("\n") {
    let line = line.trim().to_owned()
    if line.has_prefix("cmd ") {
      command = line
    }
    let value = if command == "cmd LC_BUILD_VERSION" &&
      line.has_prefix("minos ") {
      Some(line[6:].to_owned())
    } else if command == "cmd LC_VERSION_MIN_MACOSX" &&
      line.has_prefix("version ") {
      Some(line[8:].to_owned())
    } else {
      None
    }
    if value is Some(value) {
      let version = macos_parse_minimum_version(value)
      if version > minimum {
        minimum = version
      }
    }
  }
  minimum
}

///|
/// Inspect the finished staging tree, including framework/helper payloads added
/// by prepare(). Symlink aliases must not cause recursion through a framework.
async fn macos_bundle_minimum_version(path : String) -> Int {
  match @async_fs.kind(path, follow_symlink=false) {
    Directory => {
      let mut minimum = 0
      for
        entry in @async_fs.readdir(
          path,
          include_hidden=true,
          include_special=false,
        ) {
        let version = macos_bundle_minimum_version(path_join(path, entry))
        if version > minimum {
          minimum = version
        }
      }
      minimum
    }
    Regular => {
      let file = @async_fs.open(path, mode=ReadOnly)
      defer file.close()
      if file.size() < 4 {
        return 0
      }
      let magic = file.read_exactly_at(4, position=0)
      guard [
        b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce",
        b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
      ].contains(magic) else {
        return 0
      }
      let (code, output) = @process.collect_output_merged("/usr/bin/otool", [
        "-l", path,
      ])
      guard code == 0 else {
        raise InvalidPayload(
          detail="could not inspect Mach-O deployment target: " +
            path +
            "\n" +
            output.text(),
        )
      }
      let minimum = macos_load_command_minimum(output.text())
      guard minimum > 0 else {
        raise InvalidPayload(
          detail="Mach-O file has no macOS deployment target: " + path,
        )
      }
      minimum
    }
    _ => 0
  }
}

///|
fn macos_parse_minimum_version(value : String) -> Int raise {
  let components = value.split(".").collect()
  guard components.length() >= 2 && components.length() <= 3 else {
    raise InvalidPayload(detail="invalid macOS minimum version: " + value)
  }
  for component in components {
    guard component.length() > 0 && component.length() <= 5 else {
      raise InvalidPayload(detail="invalid macOS minimum version: " + value)
    }
    for char in component {
      guard char >= '0' && char <= '9' else {
        raise InvalidPayload(detail="invalid macOS minimum version: " + value)
      }
    }
  }
  let major = @string.parse_int(components[0])
  let minor = @string.parse_int(components[1])
  let patch = if components.length() == 3 {
    @string.parse_int(components[2])
  } else {
    0
  }
  guard major > 0 &&
    major <= 32767 &&
    minor >= 0 &&
    minor <= 255 &&
    patch >= 0 &&
    patch <= 255 else {
    raise InvalidPayload(detail="invalid macOS minimum version: " + value)
  }
  major * 65536 + minor * 256 + patch
}

///|
fn macos_resolve_minimum_version(
  detected : Int,
  requested : String?,
) -> String raise {
  let minimum = match requested {
    None => detected
    Some(value) => {
      let version = macos_parse_minimum_version(value)
      guard version >= detected else {
        raise InvalidPayload(
          detail="requested macOS minimum " +
            value +
            " is below packaged binary requirement " +
            macos_format_minimum_version(detected),
        )
      }
      version
    }
  }
  macos_format_minimum_version(minimum)
}

///|
fn macos_format_minimum_version(version : Int) -> String {
  "\{version / 65536}.\{version / 256 % 256}.\{version % 256}"
}
