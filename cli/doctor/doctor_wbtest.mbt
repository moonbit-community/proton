///|
fn ensure_test_dir(path : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(path) catch {
    _ => ()
  }
}

///|
test "moon_config adapter reads module deps and package imports" {
  let dir = "target/proton-doctor-config"
  ensure_test_dir(dir)
  let moon_mod_path = path_join(dir, "moon.mod")
  let moon_pkg_path = path_join(dir, "moon.pkg")
  @mbfs.write_string_to_file(
    moon_mod_path,
    (
      #|name = "justjavac/proton-demo"
      #|
      #|version = "0.1.0"
      #|
      #|import {
      #|  "justjavac/proton@0.1.10",
      #|  "justjavac/proton_ext@0.1.0",
      #|  "moonbitlang/async@0.19.0",
      #|  "moonbitlang/x@0.4.43",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    moon_pkg_path,
    (
      #|import {
      #|  "justjavac/proton",
      #|  "justjavac/proton_ext/fs" @fs,
      #|}
      #|
      #|options(
      #|  "is-main": true,
      #|  "bin-name": "demo",
      #|)
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let module_config = read_moon_mod(moon_mod_path).unwrap()
  @debug.assert_eq(module_config.name, Some("justjavac/proton-demo"))
  @debug.assert_eq(
    dependency_version(Some(module_config), "justjavac/proton"),
    Some("0.1.10"),
  )
  let package_config = read_moon_pkg(moon_pkg_path).unwrap()
  assert_true(package_has_import(Some(package_config), "justjavac/proton"))
  @debug.assert_eq(
    package_imports_with_prefix(Some(package_config), "justjavac/proton_ext/"),
    ["justjavac/proton_ext/fs"],
  )
}

///|
test "moon_config adapter reports parse failures" {
  let dir = "target/proton-doctor-bad-config"
  ensure_test_dir(dir)
  let moon_mod_path = path_join(dir, "moon.mod")
  @mbfs.write_string_to_file(
    moon_mod_path,
    (
      #|name =
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match read_moon_mod(moon_mod_path) {
    Err(ParseFailed(path, message)) => {
      assert_eq(path, moon_mod_path)
      assert_true(message.length() > 0)
    }
    _ => abort("expected ParseFailed")
  }
}

///|
test "text renderer uses utf8 symbols and dry run note" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("Environment", Ok, [
        DoctorLine::new(Ok, "OS: Windows x86_64"),
        DoctorLine::new(Warn, "MSVC: not found", hint="install Visual Studio"),
      ]),
    ],
    dry_run=true,
  )
  inspect(
    render_doctor_text(report),
    content=(
      #|✓ Environment
      #|  ✓ OS: Windows x86_64
      #|  ! MSVC: not found
      #|    hint: install Visual Studio
      #|
      #|- doctor is read-only; no files will be changed
      #|
    ),
  )
}

///|
test "json renderer does not include utf8 status symbols" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("Packages", Missing, [
        DoctorLine::new(Missing, "justjavac/proton: not declared"),
      ]),
    ],
    dry_run=false,
  )
  let rendered = render_doctor_json(report)
  assert_false(rendered.contains("✓"))
  assert_false(rendered.contains("✗"))
  assert_true(rendered.contains("\"status\": \"missing\""))
  assert_true(rendered.contains("\"schema_version\": 1"))
}
