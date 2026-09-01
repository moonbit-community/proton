// The Windows installer target. The generated NSIS script is intentionally
// repeatable so it can replace an existing installation.

///|
/// NSIS derives the silent-install switch (`/S`) itself.
let windows_installer_tool : String = "makensis"

///|
fn windows_installer_path(plan : PackageSpec) -> String {
  resolve_path(plan.output, "\{executable_name(plan.product_name)}-setup.exe")
}

///|
fn windows_installer_staging_path(plan : PackageSpec) -> String {
  resolve_path(
    plan.output,
    ".\{executable_name(plan.product_name)}.staging-setup.exe",
  )
}

///|
fn windows_installer_script_path(plan : PackageSpec) -> String {
  resolve_path(
    plan.output,
    ".\{executable_name(plan.product_name)}.installer.nsi",
  )
}

///|
/// The registry key holding the install location. The updater does not read
/// it — it re-runs the installer, which resolves the location itself — but
/// Add/Remove Programs and a manual reinstall both do.
fn windows_installer_registry_key(plan : PackageSpec) -> String {
  "Software\\\{plan.identifier}"
}

///|
fn windows_uninstall_registry_key(plan : PackageSpec) -> String {
  "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\{plan.identifier}"
}

///|
fn windows_protocol_install_script(
  plan : PackageSpec,
  executable : String,
) -> String {
  let builder = StringBuilder()
  for scheme in plan.url_schemes {
    let scheme = windows_installer_quote(scheme)
    builder <+
      $|  WriteRegStr HKCU "Software\\Classes\\\{scheme}" "" "URL:\{scheme}"
    builder.write_char('\n')
    builder <+
      $|  WriteRegStr HKCU "Software\\Classes\\\{scheme}" "URL Protocol" ""
    builder.write_char('\n')
    builder <+
      $|  WriteRegStr HKCU "Software\\Classes\\\{scheme}\\shell\\open\\command" "" "$\\"$INSTDIR\\\{executable}$\\" $\\"%1$\\""
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn windows_protocol_uninstall_script(plan : PackageSpec) -> String {
  let builder = StringBuilder()
  for scheme in plan.url_schemes {
    builder <+
      $|  DeleteRegKey HKCU "Software\\Classes\\\{windows_installer_quote(scheme)}"
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
/// `VIProductVersion` rejects anything that is not exactly four numeric
/// fields, so a semantic version has to be padded and any pre-release suffix
/// dropped. The human-readable version still ships in `FileVersion`.
fn windows_installer_version_quad(version : String) -> String {
  let digits = []
  let current = StringBuilder()
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
fn windows_installer_script(plan : PackageSpec, source : String) -> String {
  let product = windows_installer_quote(plan.product_name)
  let executable = "\{executable_name(plan.product_name)}.exe"
  let builder = StringBuilder()
  builder <+
    #|Unicode true
    #|ManifestDPIAware true
    #|SetCompressor /SOLID lzma
    #|RequestExecutionLevel admin
    #|
    #|!include "FileFunc.nsh"
    #|!include "LogicLib.nsh"
    #|!include "MUI2.nsh"
    #|
    #|Var ProtonUpdate
    #|Var ProtonUpdatePid
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
    #|Function .onInit
    #|  ${GetParameters} $R0
    #|  ${GetOptions} $R0 "/PROTON-UPDATE=" $ProtonUpdate
    #|  ${GetOptions} $R0 "/PROTON-PID=" $ProtonUpdatePid
    #|  ${If} $ProtonUpdate == "1"
    #|  ${AndIf} $ProtonUpdatePid == ""
    #|    Abort "The update process id is missing."
    #|  ${EndIf}
    #|FunctionEnd
    #|
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
    $|  ; Expand the complete release beside the installed tree before moving
    $|  ; either one. A failed extraction therefore leaves the old app intact.
    $|  RMDir /r "$INSTDIR.proton-next"
    $|  SetOutPath "$INSTDIR.proton-next"
    $|  ClearErrors
    $|  File /r "\{windows_installer_quote(source)}\\*.*"
    $|  IfErrors install_failed
    $|  ClearErrors
    $|  WriteUninstaller "$INSTDIR.proton-next\\Uninstall.exe"
    $|  IfErrors install_failed
    $|
    $|  ; Reaching a later update proves the current tree started successfully,
    $|  ; so its predecessor is no longer needed as the recovery copy.
    $|  RMDir /r "$INSTDIR.proton-previous"
    $|  IfFileExists "$INSTDIR\\*.*" 0 promote_update
    $|  ; The updater names the exact process tree it is replacing. A manual
    $|  ; reinstall has no such token and falls back to the executable name.
    $|  ${If} $ProtonUpdate == "1"
    $|    nsExec::Exec 'taskkill /F /T /PID "$ProtonUpdatePid"'
    $|  ${Else}
    $|    nsExec::Exec 'taskkill /F /T /IM "\{executable}"'
    $|  ${EndIf}
    $|  Pop $0
    $|  Sleep 500
    $|  ClearErrors
    $|  Rename "$INSTDIR" "$INSTDIR.proton-previous"
    $|  IfErrors install_failed
    $|promote_update:
    $|  ClearErrors
    $|  Rename "$INSTDIR.proton-next" "$INSTDIR"
    $|  IfErrors 0 install_complete
    $|  Rename "$INSTDIR.proton-previous" "$INSTDIR"
    $|  Abort "The new installation could not be moved into place."
    $|install_failed:
    $|  RMDir /r "$INSTDIR.proton-next"
    $|  Abort "The update could not be installed."
    $|install_complete:
    $|  SetOutPath "$INSTDIR"
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
  builder.write_char('\n')
  builder.write_string(windows_protocol_install_script(plan, executable))
  builder <+
    $|  CreateShortCut "$SMPROGRAMS\\\{product}.lnk" "$INSTDIR\\\{executable}"
    $|  ${If} $ProtonUpdate == "1"
    $|    Exec '"$INSTDIR\\\{executable}"'
    $|    Delete /REBOOTOK "$EXEPATH"
    $|  ${EndIf}
    $|SectionEnd
    $|
  builder <+
    $|Section "Uninstall"
    $|  nsExec::Exec 'taskkill /F /IM "\{executable}"'
    $|  Pop $0
    $|  Delete "$SMPROGRAMS\\\{product}.lnk"
    $|  RMDir /r "$INSTDIR"
    $|  RMDir /r "$INSTDIR.proton-previous"
    $|  RMDir /r "$INSTDIR.proton-next"
    $|  DeleteRegKey HKLM "\{windows_installer_quote(windows_installer_registry_key(plan))}"
    $|  DeleteRegKey HKLM "\{windows_installer_quote(windows_uninstall_registry_key(plan))}"
  builder.write_char('\n')
  builder.write_string(windows_protocol_uninstall_script(plan))
  builder <+
    $|SectionEnd
    $|
  builder.to_string()
}

///|
/// Builds the installer from an already-staged portable directory.
async fn create_windows_installer(
  plan : PackageSpec,
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
        detail="\{script}: \{@debug.render(Repr(error))}",
      )
  }
  let (code, output) = @process.collect_output_merged(windows_installer_tool, [
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
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
  guard path_exists(staging) else {
    raise WindowsPackagingError::Verification(
      detail="installer was not produced: \{staging}",
    )
  }
  promote(staging, installer)
  if announce {
    println("Created installer: \{installer}")
  }
  ()
}
