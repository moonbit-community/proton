// The Windows installer target.
//
// This exists because the updater needs something to re-run. A portable ZIP
// has no install location of record and no way to replace a running tree, so
// `proton_update_install` on Windows re-invokes this installer silently and
// lets it do the replacing. Everything the script does must therefore be safe
// to repeat over an existing installation.

///|
/// NSIS derives the silent-install switch (`/S`) itself, so the updater needs
/// no cooperation from the script beyond tolerating a running application.
let windows_installer_tool : String = "makensis"

///|
fn windows_installer_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    package_executable_name(plan.product_name) + "-setup.exe",
  )
}

///|
fn windows_installer_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging-setup.exe",
  )
}

///|
fn windows_installer_script_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".installer.nsi",
  )
}

///|
/// The registry key holding the install location. The updater does not read
/// it — it re-runs the installer, which resolves the location itself — but
/// Add/Remove Programs and a manual reinstall both do.
fn windows_installer_registry_key(plan : PackagePlan) -> String {
  "Software\\" + plan.identifier
}

///|
fn windows_uninstall_registry_key(plan : PackagePlan) -> String {
  "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + plan.identifier
}

///|
/// `VIProductVersion` rejects anything that is not exactly four numeric
/// fields, so a semantic version has to be padded and any pre-release suffix
/// dropped. The human-readable version still ships in `FileVersion`.
fn windows_installer_version_quad(version : String) -> String {
  let digits = []
  let current = StringBuilder::new()
  for char in version {
    if char.is_ascii_digit() {
      current.write_char(char)
    } else {
      if current.to_string() != "" {
        digits.push(current.to_string())
        current.reset()
      }
      if char != '.' {
        break
      }
    }
  }
  if current.to_string() != "" {
    digits.push(current.to_string())
  }
  while digits.length() < 4 {
    digits.push("0")
  }
  let quad = digits[:4]
  quad.to_owned().join(".")
}

///|
/// Escapes a value for an NSIS double-quoted string.
///
/// `$` opens a variable reference such as `$INSTDIR` and is doubled to stay
/// literal; a quote is written `$\"`. The `$` pass has to run first, or it
/// would go back over the `$` that the quote escape just introduced.
/// Backslashes are ordinary characters here and must be left alone, otherwise
/// every Windows path in the script breaks.
fn windows_installer_quote(value : String) -> String {
  value.replace_all(old="$", new="$$").replace_all(old="\"", new="$\\\"")
}

///|
/// Renders the installer script.
///
/// Kept pure so the generated text is testable on any host; running
/// `makensis` needs Windows tooling that only the packaging step has.
fn windows_installer_script(plan : PackagePlan, source : String) -> String {
  let product = windows_installer_quote(plan.product_name)
  let executable = package_executable_name(plan.product_name) + ".exe"
  let builder = StringBuilder::new()
  builder <+
    #|Unicode true
    #|ManifestDPIAware true
    #|SetCompressor /SOLID lzma
    #|RequestExecutionLevel admin
    #|
    #|!include "MUI2.nsh"
    #|
  builder <+
    $|Name "\{product}"
    $|OutFile "\{windows_installer_quote(windows_installer_staging_path(plan))}"
    $|InstallDir "$PROGRAMFILES64\\\{product}"
    $|InstallDirRegKey HKLM "\{windows_installer_quote(windows_installer_registry_key(plan))}" "InstallDir"
    $|
    $|VIProductVersion "\{windows_installer_version_quad(plan.version)}"
    $|VIAddVersionKey "ProductName" "\{product}"
    $|VIAddVersionKey "FileVersion" "\{windows_installer_quote(plan.version)}"
    $|VIAddVersionKey "ProductVersion" "\{windows_installer_quote(plan.version)}"
    $|VIAddVersionKey "FileDescription" "\{product} Setup"
    $|
  builder <+
    #|!define MUI_ABORTWARNING
    #|!insertmacro MUI_PAGE_DIRECTORY
    #|!insertmacro MUI_PAGE_INSTFILES
    #|!insertmacro MUI_UNPAGE_CONFIRM
    #|!insertmacro MUI_UNPAGE_INSTFILES
    #|!insertmacro MUI_LANGUAGE "English"
    #|
    #|Section "Install"
    #|
  builder <+
    $|  ; An update re-runs this installer while the application it is
    $|  ; replacing is still running, so close it before overwriting.
    $|  nsExec::Exec 'taskkill /F /IM "\{executable}"'
    $|  Pop $0
    $|  Sleep 500
    $|
    $|  SetOutPath "$INSTDIR"
    $|  File /r "\{windows_installer_quote(source)}\\*.*"
    $|  WriteUninstaller "$INSTDIR\\Uninstall.exe"
    $|
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_installer_registry_key(plan))}" "InstallDir" "$INSTDIR"
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_installer_registry_key(plan))}" "Version" "\{windows_installer_quote(plan.version)}"
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayName" "\{product}"
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayVersion" "\{windows_installer_quote(plan.version)}"
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "UninstallString" "$\\"$INSTDIR\\Uninstall.exe$\\""
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "InstallLocation" "$INSTDIR"
    $|  WriteRegStr HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayIcon" "$INSTDIR\\\{executable}"
    $|  WriteRegDWORD HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "NoModify" 1
    $|  WriteRegDWORD HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "NoRepair" 1
    $|
    $|  CreateShortCut "$SMPROGRAMS\\\{product}.lnk" "$INSTDIR\\\{executable}"
    $|SectionEnd
    $|
  builder <+
    $|Section "Uninstall"
    $|  nsExec::Exec 'taskkill /F /IM "\{executable}"'
    $|  Pop $0
    $|  Delete "$SMPROGRAMS\\\{product}.lnk"
    $|  RMDir /r "$INSTDIR"
    $|  DeleteRegKey HKLM "\{windows_installer_quote(windows_installer_registry_key(plan))}"
    $|  DeleteRegKey HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}"
    $|SectionEnd
    $|
  builder.to_string()
}

///|
/// Builds the installer from an already-staged portable directory.
async fn create_windows_installer(
  plan : PackagePlan,
  source : String,
  announce : Bool,
) -> Unit {
  let installer = windows_installer_path(plan)
  let staging = windows_installer_staging_path(plan)
  let script = windows_installer_script_path(plan)
  remove_tree(staging)
  @async_fs.write_file(
    script,
    windows_installer_script(plan, source),
    create_mode=CreateOrTruncate,
  ) catch {
    error =>
      raise WindowsPackagingError::ToolFailure(
        stage="write Windows installer script",
        detail=script + ": " + @debug.render(Repr(error)),
      )
  }
  let (code, _) = @process.collect_output_merged(windows_installer_tool, [
    "/V2", script,
  ]) catch {
    _ =>
      raise WindowsPackagingError::ToolFailure(
        stage="create Windows installer",
        detail="\{windows_installer_tool} is not available; install NSIS to build the installer target",
      )
  }
  guard code == 0 else {
    raise WindowsPackagingError::ToolFailure(
      stage="create Windows installer",
      detail="exit code " + code.to_string(),
    )
  }
  guard @fsutil.path_exists(staging) else {
    raise WindowsPackagingError::Verification(
      detail="installer was not produced: " + staging,
    )
  }
  promote_windows_artifact(staging, installer, "Windows installer")
  if announce {
    println("Created installer: " + installer)
  }
  ()
}
