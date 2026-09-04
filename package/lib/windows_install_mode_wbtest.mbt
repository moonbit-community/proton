///|
test "NSIS modes use Tauri-compatible names and default to current user" {
  assert_eq(package_test_spec([Nsis]).nsis_install_mode, CurrentUser)
  for
    entry in [
      ("currentUser", CurrentUser),
      ("perMachine", PerMachine),
      ("both", Both),
    ] {
    let (name, mode) = entry
    assert_eq(NsisInstallMode::parse(name), mode)
    assert_eq(mode.to_string(), name)
  }
  try NsisInstallMode::parse("admin") catch {
    error => assert_eq(error, UnsupportedNsisInstallMode(value="admin"))
  } noraise {
    _ => fail("expected an invalid NSIS mode")
  }
}

///|
test "NSIS installation scopes wire permissions contexts and pages" {
  let output_path = windows_installer_quote(
    windows_installer_staging_path(package_test_spec([Nsis])),
  )
  let (current_header, current_body) = windows_installer_script(
      package_test_spec([Nsis]),
      "C:\\stage\\Demo App",
    )
    .replace_all(old=output_path, new="demo-app-setup.exe")
    .split_once("Section \"Install\"\n")
    .unwrap()
  inspect(
    current_header.to_owned(),
    content=(
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
      #|Name "Demo App"
      #|OutFile "demo-app-setup.exe"
      #|RequestExecutionLevel user
      #|InstallDir "$LOCALAPPDATA\Demo App"
      #|InstallDirRegKey HKCU "Software\dev.proton.demo" "InstallDir"
      #|
      #|VIProductVersion "1.2.3.0"
      #|VIAddVersionKey "ProductName" "Demo App"
      #|VIAddVersionKey "FileVersion" "1.2.3"
      #|VIAddVersionKey "ProductVersion" "1.2.3"
      #|VIAddVersionKey "FileDescription" "Demo App Setup"
      #|Function .onInit
      #|  SetShellVarContext current
      #|  ${GetParameters} $R0
      #|  ${GetOptions} $R0 "/PROTON-UPDATE=" $ProtonUpdate
      #|  ${GetOptions} $R0 "/PROTON-PID=" $ProtonUpdatePid
      #|  ${If} $ProtonUpdate == "1"
      #|  ${AndIf} $ProtonUpdatePid == ""
      #|    Abort "The update process id is missing."
      #|  ${EndIf}
      #|FunctionEnd
      #|
      #|Function un.onInit
      #|  SetShellVarContext current
      #|FunctionEnd
      #|
      #|!define MUI_ABORTWARNING
      #|!insertmacro MUI_PAGE_DIRECTORY
      #|!insertmacro MUI_PAGE_INSTFILES
      #|!insertmacro MUI_UNPAGE_CONFIRM
      #|!insertmacro MUI_UNPAGE_INSTFILES
      #|!insertmacro MUI_LANGUAGE "English"
      #|
      #|
    ),
  )
  let (machine_header, machine_body) = windows_installer_script(
      package_test_spec([Nsis], nsis_install_mode=PerMachine),
      "C:\\stage\\Demo App",
    )
    .replace_all(old=output_path, new="demo-app-setup.exe")
    .split_once("Section \"Install\"\n")
    .unwrap()
  inspect(
    machine_header.to_owned(),
    content=(
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
      #|Name "Demo App"
      #|OutFile "demo-app-setup.exe"
      #|RequestExecutionLevel admin
      #|InstallDir "$PROGRAMFILES64\Demo App"
      #|InstallDirRegKey HKLM "Software\dev.proton.demo" "InstallDir"
      #|
      #|VIProductVersion "1.2.3.0"
      #|VIAddVersionKey "ProductName" "Demo App"
      #|VIAddVersionKey "FileVersion" "1.2.3"
      #|VIAddVersionKey "ProductVersion" "1.2.3"
      #|VIAddVersionKey "FileDescription" "Demo App Setup"
      #|Function .onInit
      #|  SetShellVarContext all
      #|  ${GetParameters} $R0
      #|  ${GetOptions} $R0 "/PROTON-UPDATE=" $ProtonUpdate
      #|  ${GetOptions} $R0 "/PROTON-PID=" $ProtonUpdatePid
      #|  ${If} $ProtonUpdate == "1"
      #|  ${AndIf} $ProtonUpdatePid == ""
      #|    Abort "The update process id is missing."
      #|  ${EndIf}
      #|FunctionEnd
      #|
      #|Function un.onInit
      #|  SetShellVarContext all
      #|FunctionEnd
      #|
      #|!define MUI_ABORTWARNING
      #|!insertmacro MUI_PAGE_DIRECTORY
      #|!insertmacro MUI_PAGE_INSTFILES
      #|!insertmacro MUI_UNPAGE_CONFIRM
      #|!insertmacro MUI_UNPAGE_INSTFILES
      #|!insertmacro MUI_LANGUAGE "English"
      #|
      #|
    ),
  )
  assert_eq(machine_body.to_owned(), current_body.to_owned())
  let (both_header, both_body) = windows_installer_script(
      package_test_spec([Nsis], nsis_install_mode=Both),
      "C:\\stage\\Demo App",
    )
    .replace_all(old=output_path, new="demo-app-setup.exe")
    .split_once("Section \"Install\"\n")
    .unwrap()
  inspect(
    both_header.to_owned(),
    content=(
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
      #|Name "Demo App"
      #|OutFile "demo-app-setup.exe"
      #|!define MULTIUSER_MUI
      #|!define MULTIUSER_EXECUTIONLEVEL Highest
      #|!define MULTIUSER_INSTALLMODE_COMMANDLINE
      #|!define MULTIUSER_USE_PROGRAMFILES64
      #|!define MULTIUSER_INSTALLMODE_INSTDIR "Demo App"
      #|!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_KEY "Software\dev.proton.demo"
      #|!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "InstallDir"
      #|!define MULTIUSER_INSTALLMODE_FUNCTION ProtonRestoreInstallDir
      #|!include "MultiUser.nsh"
      #|InstallDir "placeholder\Demo App"
      #|Var ProtonInstallDirOverride
      #|
      #|Function ProtonRestoreInstallDir
      #|  ReadRegStr $0 SHCTX "Software\dev.proton.demo" "InstallDir"
      #|  ${If} $0 != ""
      #|    StrCpy $INSTDIR $0
      #|  ${EndIf}
      #|  ${If} $ProtonInstallDirOverride != "placeholder\Demo App"
      #|    StrCpy $INSTDIR $ProtonInstallDirOverride
      #|  ${EndIf}
      #|FunctionEnd
      #|
      #|VIProductVersion "1.2.3.0"
      #|VIAddVersionKey "ProductName" "Demo App"
      #|VIAddVersionKey "FileVersion" "1.2.3"
      #|VIAddVersionKey "ProductVersion" "1.2.3"
      #|VIAddVersionKey "FileDescription" "Demo App Setup"
      #|Function .onInit
      #|  StrCpy $ProtonInstallDirOverride $INSTDIR
      #|  !insertmacro MULTIUSER_INIT
      #|  ${GetParameters} $R0
      #|  ${GetOptions} $R0 "/PROTON-UPDATE=" $ProtonUpdate
      #|  ${GetOptions} $R0 "/PROTON-PID=" $ProtonUpdatePid
      #|  ${If} $ProtonUpdate == "1"
      #|  ${AndIf} $ProtonUpdatePid == ""
      #|    Abort "The update process id is missing."
      #|  ${EndIf}
      #|  ${If} $ProtonUpdate == "1"
      #|    ${If} $ProtonInstallDirOverride == "placeholder\Demo App"
      #|      Abort "The update installation directory is missing."
      #|    ${EndIf}
      #|    ReadRegStr $0 HKCU "Software\dev.proton.demo" "InstallDir"
      #|    ReadRegStr $1 HKLM "Software\dev.proton.demo" "InstallDir"
      #|    ${If} $0 == $ProtonInstallDirOverride
      #|    ${AndIf} $1 != $ProtonInstallDirOverride
      #|      Call MultiUser.InstallMode.CurrentUser
      #|    ${ElseIf} $1 == $ProtonInstallDirOverride
      #|    ${AndIf} $0 != $ProtonInstallDirOverride
      #|      Call MultiUser.InstallMode.AllUsers
      #|      ${If} $MultiUser.InstallMode != "AllUsers"
      #|        Abort "The update requires administrator privileges."
      #|      ${EndIf}
      #|    ${Else}
      #|      Abort "The update installation scope could not be determined."
      #|    ${EndIf}
      #|  ${EndIf}
      #|FunctionEnd
      #|
      #|Function un.onInit
      #|  !insertmacro MULTIUSER_UNINIT
      #|  ReadRegStr $0 HKCU "Software\dev.proton.demo" "InstallDir"
      #|  ${If} $0 == $INSTDIR
      #|    Call un.MultiUser.InstallMode.CurrentUser
      #|  ${Else}
      #|    ReadRegStr $0 HKLM "Software\dev.proton.demo" "InstallDir"
      #|    ${If} $0 == $INSTDIR
      #|      Call un.MultiUser.InstallMode.AllUsers
      #|    ${EndIf}
      #|  ${EndIf}
      #|FunctionEnd
      #|
      #|!define MUI_ABORTWARNING
      #|!insertmacro MULTIUSER_PAGE_INSTALLMODE
      #|!insertmacro MUI_PAGE_DIRECTORY
      #|!insertmacro MUI_PAGE_INSTFILES
      #|!insertmacro MUI_UNPAGE_CONFIRM
      #|!insertmacro MUI_UNPAGE_INSTFILES
      #|!insertmacro MUI_LANGUAGE "English"
      #|
      #|
    ),
  )
  assert_eq(
    both_body.to_owned(),
    current_body
    .to_owned()
    .replace_all(
      old="Uninstall.exe$\\\"\"",
      new="Uninstall.exe$\\\" /$MultiUser.InstallMode\"",
    ),
  )
  let (_, registration) = current_body
    .to_owned()
    .split_once("install_complete:\n")
    .unwrap()
  inspect(
    registration.to_owned(),
    content=(
      #|  SetOutPath "$INSTDIR"
      #|
      #|  WriteRegStr SHCTX "Software\dev.proton.demo" "InstallDir" "$INSTDIR"
      #|  WriteRegStr SHCTX "Software\dev.proton.demo" "Version" "1.2.3"
      #|  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "DisplayName" "Demo App"
      #|  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "DisplayVersion" "1.2.3"
      #|  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
      #|  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "InstallLocation" "$INSTDIR"
      #|  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "DisplayIcon" "$INSTDIR\demo-app.exe"
      #|  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "NoModify" 1
      #|  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo" "NoRepair" 1
      #|
      #|  WriteRegStr SHCTX "Software\Classes\devtoys" "" "URL:devtoys"
      #|  WriteRegStr SHCTX "Software\Classes\devtoys" "URL Protocol" ""
      #|  WriteRegStr SHCTX "Software\Classes\devtoys\shell\open\command" "" "$\"$INSTDIR\demo-app.exe$\" $\"%1$\""
      #|  CreateShortCut "$SMPROGRAMS\Demo App.lnk" "$INSTDIR\demo-app.exe"
      #|  ${If} $ProtonUpdate == "1"
      #|    Exec '"$INSTDIR\demo-app.exe"'
      #|    Delete /REBOOTOK "$EXEPATH"
      #|  ${EndIf}
      #|SectionEnd
      #|Section "Uninstall"
      #|  nsExec::Exec 'taskkill /F /IM "demo-app.exe"'
      #|  Pop $0
      #|  Delete "$SMPROGRAMS\Demo App.lnk"
      #|  RMDir /r "$INSTDIR"
      #|  RMDir /r "$INSTDIR.proton-previous"
      #|  RMDir /r "$INSTDIR.proton-next"
      #|  DeleteRegKey SHCTX "Software\dev.proton.demo"
      #|  DeleteRegKey SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\dev.proton.demo"
      #|  ReadRegStr $0 SHCTX "Software\Classes\devtoys\shell\open\command" ""
      #|  ${If} $0 == "$\"$INSTDIR\demo-app.exe$\" $\"%1$\""
      #|    DeleteRegKey SHCTX "Software\Classes\devtoys"
      #|  ${EndIf}
      #|SectionEnd
      #|
    ),
  )
}
