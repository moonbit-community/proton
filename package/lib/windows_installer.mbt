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
fn windows_protocol_command(executable : String) -> String {
  "$\\\"$INSTDIR\\\{executable}$\\\" $\\\"%1$\\\""
}

///|
fn windows_protocol_install_script(
  plan : PackageSpec,
  executable : String,
) -> String {
  let builder = StringBuilder()
  let command = windows_protocol_command(executable)
  for scheme in plan.url_schemes {
    let scheme = windows_installer_quote(scheme)
    builder <+
      $|  WriteRegStr SHCTX "Software\\Classes\\\{scheme}" "" "URL:\{scheme}"
    builder.write_char('\n')
    builder <+
      $|  WriteRegStr SHCTX "Software\\Classes\\\{scheme}" "URL Protocol" ""
    builder.write_char('\n')
    builder <+
      $|  WriteRegStr SHCTX "Software\\Classes\\\{scheme}\\shell\\open\\command" "" "\{command}"
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn windows_protocol_uninstall_script(
  plan : PackageSpec,
  executable : String,
) -> String {
  let builder = StringBuilder()
  let command = windows_protocol_command(executable)
  for scheme in plan.url_schemes {
    let scheme = windows_installer_quote(scheme)
    builder <+
      $|  ReadRegStr $0 SHCTX "Software\\Classes\\\{scheme}\\shell\\open\\command" ""
    builder.write_char('\n')
    builder <+
      $|  ${If} $0 == "\{command}"
    builder.write_char('\n')
    builder <+
      $|    DeleteRegKey SHCTX "Software\\Classes\\\{scheme}"
    builder.write_char('\n')
    builder <+
      #|  ${EndIf}
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
    #|
    #|!include "FileFunc.nsh"
    #|!include "LogicLib.nsh"
    #|!include "MUI2.nsh"
    #|
    #|Var ProtonUpdate
    #|Var ProtonUpdatePid
    #|Var ProtonUpdateCreated
    #|Var ProtonUpdateLock
    #|Var ProtonUpdateReady
    #|Var ProtonInstanceLock
    #|
  builder <+
    $|Name "\{product}"
    $|OutFile "\{windows_installer_quote(windows_installer_staging_path(plan))}"
    $|
  builder.write_string(windows_install_mode_header(plan))
  builder <+
    $|
    $|VIProductVersion "\{windows_installer_version_quad(plan.version)}"
    $|VIAddVersionKey "ProductName" "\{product}"
    $|VIAddVersionKey "FileVersion" "\{windows_installer_quote(plan.version)}"
    $|VIAddVersionKey "ProductVersion" "\{windows_installer_quote(plan.version)}"
    $|VIAddVersionKey "FileDescription" "\{product} Setup"
    $|
  builder <+
    #|Function .onInit
    #|
  builder.write_string(windows_install_mode_init(plan, false))
  builder <+
    #|  ${GetParameters} $R0
    #|  ${GetOptions} $R0 "/PROTON-UPDATE=" $ProtonUpdate
    #|  ${GetOptions} $R0 "/PROTON-PID=" $ProtonUpdatePid
    #|  ${GetOptions} $R0 "/PROTON-CREATED=" $ProtonUpdateCreated
    #|  ${GetOptions} $R0 "/PROTON-LOCK=" $ProtonUpdateLock
    #|  ${GetOptions} $R0 "/PROTON-READY=" $ProtonUpdateReady
    #|  ${If} $ProtonUpdate == "1"
    #|  ${AndIf} $ProtonUpdatePid == ""
    #|    Abort "The update process id is missing."
    #|  ${EndIf}
    #|
  builder.write_string(windows_install_mode_update_init(plan))
  builder <+
    #|  ; Duplicate the old instance's reservation before acknowledging handoff.
    #|  ; Closing the old process must never expose an unreserved installation.
    #|  ${If} $ProtonUpdate == "1"
    #|  ${AndIf} $ProtonUpdateLock != ""
    #|  ${AndIf} $ProtonUpdateLock != "0"
    #|    System::Call 'kernel32::OpenProcess(i 0x1040, i 0, i $ProtonUpdatePid) p .r0'
    #|    ${If} $0 == 0
    #|      Abort "Could not open the application for instance handoff."
    #|    ${EndIf}
    #|    System::Call 'kernel32::GetProcessTimes(p r0, *l .r2, *l .r3, *l .r4, *l .r5) i .r1'
    #|    ${If} $1 == 0
    #|    ${OrIf} $2 != $ProtonUpdateCreated
    #|      System::Call 'kernel32::CloseHandle(p r0)'
    #|      Abort "The updating process identity has changed."
    #|    ${EndIf}
    #|    System::Call 'kernel32::GetCurrentProcess() p .r6'
    #|    System::Call 'kernel32::DuplicateHandle(p r0, p $ProtonUpdateLock, p r6, *p .r7, i 0, i 0, i 2) i .r1'
    #|    ${If} $1 == 0
    #|      System::Call 'kernel32::CloseHandle(p r0)'
    #|      Abort "Could not retain application instance ownership."
    #|    ${EndIf}
    #|    StrCpy $ProtonInstanceLock $7
    #|    System::Call 'kernel32::DuplicateHandle(p r0, p $ProtonUpdateReady, p r6, *p .r7, i 0, i 0, i 2) i .r1'
    #|    System::Call 'kernel32::CloseHandle(p r0)'
    #|    ${If} $1 == 0
    #|      Abort "Could not acknowledge instance handoff."
    #|    ${EndIf}
    #|    System::Call 'kernel32::SetEvent(p r7) i .r1'
    #|    System::Call 'kernel32::CloseHandle(p r7)'
    #|    ${If} $1 == 0
    #|      Abort "Could not acknowledge instance handoff."
    #|    ${EndIf}
    #|  ${EndIf}
    #|FunctionEnd
    #|
    #|Function un.onInit
    #|
  builder.write_string(windows_install_mode_init(plan, true))
  builder <+
    #|FunctionEnd
    #|
    #|!define MUI_ABORTWARNING
    #|
  if plan.nsis_install_mode == Both {
    builder.write_string("!insertmacro MULTIUSER_PAGE_INSTALLMODE\n")
  }
  builder <+
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
    $|  ; SetOutPath also changes the working directory, which Windows locks.
    $|  SetOutPath "$TEMP"
    $|
    $|  ; Reaching a later update proves the current tree started successfully,
    $|  ; so its predecessor is no longer needed as the recovery copy.
    $|  RMDir /r "$INSTDIR.proton-previous"
    $|  IfFileExists "$INSTDIR\\*.*" 0 promote_update
    $|  ; Automatic updates wait for orderly shutdown. The creation time avoids
    $|  ; waiting on a reused PID. Older Proton releases supplied only the PID.
    $|  ${If} $ProtonUpdate == "1"
    $|    System::Call 'kernel32::OpenProcess(i 0x101000, i 0, i $ProtonUpdatePid) p .r0 ?e'
    $|    Pop $1
    $|    ${If} $0 == 0
    $|      ${If} $1 != 87
    $|        Abort "Could not wait for the application to exit (error $1)."
    $|      ${EndIf}
    $|    ${Else}
    $|      ${If} $ProtonUpdateCreated != ""
    $|        System::Call 'kernel32::GetProcessTimes(p r0, *l .r2, *l .r3, *l .r4, *l .r5) i .r1'
    $|        ${If} $1 == 0
    $|          System::Call 'kernel32::CloseHandle(p r0)'
    $|          Abort "Could not identify the application process."
    $|        ${EndIf}
    $|      ${Else}
    $|        StrCpy $2 $ProtonUpdateCreated
    $|      ${EndIf}
    $|      ${If} $2 == $ProtonUpdateCreated
    $|        System::Call 'kernel32::WaitForSingleObject(p r0, i -1) i .r1'
    $|      ${Else}
    $|        ; The original process has exited and its PID was reused.
    $|        StrCpy $1 0
    $|      ${EndIf}
    $|      System::Call 'kernel32::CloseHandle(p r0)'
    $|      ${If} $1 != 0
    $|        Abort "Could not wait for the application to exit."
    $|      ${EndIf}
    $|    ${EndIf}
    $|  ${Else}
    $|    nsExec::Exec 'taskkill /F /T /IM "\{executable}"'
    $|    Pop $0
    $|    Sleep 500
    $|  ${EndIf}
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
    $|  SetOutPath "$TEMP"
    $|  RMDir /r "$INSTDIR.proton-next"
    $|  Abort "The update could not be installed."
    $|install_complete:
    $|  SetOutPath "$INSTDIR"
    $|
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_installer_registry_key(plan))}" "InstallDir" "$INSTDIR"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_installer_registry_key(plan))}" "Version" "\{windows_installer_quote(plan.version)}"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayName" "\{product}"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayVersion" "\{windows_installer_quote(plan.version)}"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "UninstallString" "$\\"$INSTDIR\\Uninstall.exe$\\"\{if plan.nsis_install_mode == Both { " /$MultiUser.InstallMode" } else { "" }}"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "InstallLocation" "$INSTDIR"
    $|  WriteRegStr SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "DisplayIcon" "$INSTDIR\\\{executable}"
    $|  WriteRegDWORD SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "NoModify" 1
    $|  WriteRegDWORD SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}" "NoRepair" 1
    $|
  builder.write_char('\n')
  builder.write_string(windows_protocol_install_script(plan, executable))
  builder <+
    $|  CreateShortCut "$SMPROGRAMS\\\{product}.lnk" "$INSTDIR\\\{executable}"
    $|  ${If} $ProtonUpdate == "1"
    $|    ${If} $ProtonInstanceLock != ""
    $|      System::Call 'kernel32::CloseHandle(p $ProtonInstanceLock)'
    $|    ${EndIf}
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
    $|  DeleteRegKey SHCTX "\{windows_installer_quote(windows_installer_registry_key(plan))}"
    $|  DeleteRegKey SHCTX "\{windows_installer_quote(windows_uninstall_registry_key(plan))}"
  builder.write_char('\n')
  builder.write_string(windows_protocol_uninstall_script(plan, executable))
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
