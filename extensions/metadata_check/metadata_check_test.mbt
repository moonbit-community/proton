///|
/// Resolves one fixture path by searching the current directory and its parents.
fn resolve_fixture_path(candidates : Array[String]) -> String {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return resolved
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  candidates[0]
}

///|
/// Resolves the metadata file path for one built-in extension fixture.
fn extension_metadata_path(name : String) -> String {
  resolve_fixture_path([
    "../" + name + "/moon.ext",
    name + "/moon.ext",
    "extensions/" + name + "/moon.ext",
  ])
}

///|
/// Loads one built-in extension descriptor and aborts the test on failure.
fn load_descriptor(name : String) -> @catalog.ExtensionDescriptor raise {
  let descriptor = @catalog.load_extension_descriptor_from_file(
    extension_metadata_path(name),
  )
  assert_true(descriptor.metadata_path().has_suffix("moon.ext"))
  descriptor
}

///|
/// Asserts that metadata fields stay aligned with the exported extension spec.
fn assert_metadata_matches_spec(
  descriptor : @catalog.ExtensionDescriptor,
  spec : @core.ExtensionSpec,
  package_path : String,
  expected_id : String,
  expected_namespace : String,
) -> Unit raise {
  assert_eq(descriptor.id(), spec.id())
  assert_eq(descriptor.id(), expected_id)
  @debug.assert_eq(descriptor.dependencies(), spec.dependencies())
  assert_eq(descriptor.moonbit_import_path(), package_path)
  assert_eq(spec.js_namespace(), expected_namespace)
  assert_eq(descriptor.js_namespace(), expected_namespace)
  assert_true(descriptor.platforms().length() > 0)
}

///|
/// Asserts that metadata fields stay aligned with the exported app-command extension spec.
fn assert_metadata_matches_app_command_spec(
  descriptor : @catalog.ExtensionDescriptor,
  spec : @proton_command.AppCommandExtensionSpec,
  package_path : String,
  expected_id : String,
  expected_namespace : String,
) -> Unit raise {
  assert_eq(descriptor.id(), spec.id())
  assert_eq(descriptor.id(), expected_id)
  @debug.assert_eq(descriptor.dependencies(), spec.dependencies())
  assert_eq(descriptor.moonbit_import_path(), package_path)
  assert_eq(spec.js_namespace(), expected_namespace)
  assert_eq(descriptor.js_namespace(), expected_namespace)
}

///|
test "built-in extension metadata stays aligned with built-in specs" {
  assert_metadata_matches_app_command_spec(
    load_descriptor("dialog"),
    @dialog.extension().command_spec().unwrap(),
    "justjavac/proton_ext/dialog",
    "justjavac/proton-dialog",
    "dialog",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("fs"),
    @fs.extension().command_spec().unwrap(),
    "justjavac/proton_ext/fs",
    "justjavac/proton-fs",
    "fs",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("global_hotkey"),
    @global_hotkey.extension().command_spec().unwrap(),
    "justjavac/proton_ext/global_hotkey",
    "justjavac/proton-global-hotkey",
    "globalHotkey",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("keepawake"),
    @keepawake.extension().command_spec().unwrap(),
    "justjavac/proton_ext/keepawake",
    "justjavac/proton-keepawake",
    "keepAwake",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("microphone"),
    @microphone.extension().command_spec().unwrap(),
    "justjavac/proton_ext/microphone",
    "justjavac/proton-microphone",
    "microphone",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("notification"),
    @notification.extension().command_spec().unwrap(),
    "justjavac/proton_ext/notification",
    "justjavac/proton-notification",
    "notification",
  )
  assert_metadata_matches_spec(
    load_descriptor("path"),
    @path.core_spec(),
    "justjavac/proton_ext/path",
    "justjavac/proton-path",
    "path",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("shell"),
    @shell.extension().command_spec().unwrap(),
    "justjavac/proton_ext/shell",
    "justjavac/proton-shell",
    "shell",
  )
  assert_metadata_matches_app_command_spec(
    load_descriptor("tray"),
    @tray.extension().command_spec().unwrap(),
    "justjavac/proton_ext/tray",
    "justjavac/proton-tray",
    "tray",
  )
}
