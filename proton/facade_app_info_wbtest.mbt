///|
test "packaged application metadata exposes product name and version" {
  let source =
    #|{
    #|  "schema_version": 1,
    #|  "product_name": "Proton Notes",
    #|  "version": "1.2.3"
    #|}
    #|
  let metadata = packaged_application_metadata_from_json(source)
  assert_eq(metadata.name, "Proton Notes")
  assert_eq(metadata.version, "1.2.3")
}

///|
test "packaged application metadata requires non-empty fields" {
  try
    packaged_application_metadata_from_json(
      "{\"product_name\":\"Proton Notes\",\"version\":\"  \"}",
    )
  catch {
    MissingField(field="version") => ()
    _ => fail("expected the version field to be rejected")
  } noraise {
    _ => fail("expected packaged metadata validation to fail")
  }
}

///|
test "project application metadata uses package configuration" {
  let config = @proton_config.ProjectConfig(
    "/workspace/notes",
    "dev.proton.notes",
    package_config=Some(
      @proton_config.ProjectPackageConfig("  Proton Notes  ", " 1.2.3 "),
    ),
  )
  let metadata = project_application_metadata(config)
  assert_eq(metadata.name, "Proton Notes")
  assert_eq(metadata.version, "1.2.3")
}

///|
test "packaged resource roots follow each bundle layout" {
  assert_eq(
    normalize_path_separators(
      packaged_resource_dir_from_manifest(
        "/Applications/Notes.app/Contents/Resources/proton-package.json", false,
      ),
    ),
    "/Applications/Notes.app/Contents/Resources",
  )
  assert_eq(
    normalize_path_separators(
      packaged_resource_dir_from_manifest(
        "/opt/Notes/proton-package.json", true,
      ),
    ),
    "/opt/Notes/Resources",
  )
}

///|
test "project application metadata requires package configuration" {
  let config = @proton_config.ProjectConfig(
    "/workspace/notes", "dev.proton.notes",
  )
  try project_application_metadata(config) catch {
    MissingPackageMetadata => ()
    _ => fail("expected missing package metadata")
  } noraise {
    _ => fail("expected project metadata validation to fail")
  }
}

///|
test "standard home and application data roots follow platform conventions" {
  assert_eq(
    normalize_path_separators(
      home_dir_for_platform("windows", None, Some("C:/Users/test")),
    ),
    "C:/Users/test",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "macos",
        Some("/Users/test"),
        None,
        None,
      ),
    ),
    "/Users/test/Library/Application Support",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "windows",
        None,
        Some("C:/Users/test/AppData/Roaming"),
        None,
      ),
    ),
    "C:/Users/test/AppData/Roaming",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "linux",
        Some("/home/test"),
        None,
        Some("/config"),
      ),
    ),
    "/config",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "linux",
        Some("/home/test"),
        None,
        None,
      ),
    ),
    "/home/test/.config",
  )
}

///|
test "temporary path resolution uses platform environment precedence" {
  assert_eq(
    normalize_path_separators(
      temp_dir_for_platform(
        "windows",
        None,
        Some("C:/Temp"),
        Some("C:/Fallback"),
      ),
    ),
    "C:/Temp",
  )
  assert_eq(
    temp_dir_for_platform("macos", Some("/private/tmp/app"), None, None),
    "/private/tmp/app",
  )
  assert_eq(temp_dir_for_platform("linux", None, None, None), "/tmp")
}

///|
test "application root and packaged state share the package manifest probe" {
  assert_eq(app_path(), resource_dir())
  assert_eq(is_packaged(), packaged_application_manifest_path() is Some(_))
}
