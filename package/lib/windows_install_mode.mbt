///|
/// Uses NSIS's own MultiUser support for the selectable mode, as Tauri does.
fn windows_install_mode_header(plan : PackageSpec) -> String {
  let product = windows_installer_quote(plan.product_name)
  let key = windows_installer_quote(windows_installer_registry_key(plan))
  match plan.nsis_install_mode {
    CurrentUser =>
      (
        $|RequestExecutionLevel user
        $|InstallDir "$LOCALAPPDATA\{'\\'}\{product}"
        $|InstallDirRegKey HKCU "\{key}" "InstallDir"
        $|
      )
    PerMachine =>
      (
        $|RequestExecutionLevel admin
        $|InstallDir "$PROGRAMFILES64\{'\\'}\{product}"
        $|InstallDirRegKey HKLM "\{key}" "InstallDir"
        $|
      )
    Both =>
      (
        $|!define MULTIUSER_MUI
        $|!define MULTIUSER_EXECUTIONLEVEL Highest
        $|!define MULTIUSER_INSTALLMODE_COMMANDLINE
        $|!define MULTIUSER_USE_PROGRAMFILES64
        $|!define MULTIUSER_INSTALLMODE_INSTDIR "\{product}"
        $|!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_KEY "\{key}"
        $|!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "InstallDir"
        $|!define MULTIUSER_INSTALLMODE_FUNCTION ProtonRestoreInstallDir
        $|!include "MultiUser.nsh"
        $|InstallDir "placeholder\{'\\'}\{product}"
        $|Var ProtonInstallDirOverride
        $|
        $|Function ProtonRestoreInstallDir
        $|  ReadRegStr $0 SHCTX "\{key}" "InstallDir"
        $|  ${If} $0 != ""
        $|    StrCpy $INSTDIR $0
        $|  ${EndIf}
        $|  ${If} $ProtonInstallDirOverride != "placeholder\{'\\'}\{product}"
        $|    StrCpy $INSTDIR $ProtonInstallDirOverride
        $|  ${EndIf}
        $|FunctionEnd
        $|
      )
  }
}

///|
fn windows_install_mode_init(plan : PackageSpec, uninstall : Bool) -> String {
  match plan.nsis_install_mode {
    CurrentUser =>
      (
        #|  SetShellVarContext current
        #|
      )
    PerMachine =>
      (
        #|  SetShellVarContext all
        #|
      )
    Both if !uninstall =>
      (
        #|  StrCpy $ProtonInstallDirOverride $INSTDIR
        #|  !insertmacro MULTIUSER_INIT
        #|
      )
    Both => {
      let key = windows_installer_quote(windows_installer_registry_key(plan))
      // A directly launched uninstaller must use its own tree's scope even
      // when the product is installed in both HKCU and HKLM.
      (
        $|  !insertmacro MULTIUSER_UNINIT
        $|  ReadRegStr $0 HKCU "\{key}" "InstallDir"
        $|  ${If} $0 == $INSTDIR
        $|    Call un.MultiUser.InstallMode.CurrentUser
        $|  ${Else}
        $|    ReadRegStr $0 HKLM "\{key}" "InstallDir"
        $|    ${If} $0 == $INSTDIR
        $|      Call un.MultiUser.InstallMode.AllUsers
        $|    ${EndIf}
        $|  ${EndIf}
        $|
      )
    }
  }
}

///|
/// Bind silent updates to the caller's /D directory, not MultiUser's default.
fn windows_install_mode_update_init(plan : PackageSpec) -> String {
  if plan.nsis_install_mode != Both {
    return ""
  }
  let product = windows_installer_quote(plan.product_name)
  let key = windows_installer_quote(windows_installer_registry_key(plan))
  (
    $|  ${If} $ProtonUpdate == "1"
    $|    ${If} $ProtonInstallDirOverride == "placeholder\{'\\'}\{product}"
    $|      Abort "The update installation directory is missing."
    $|    ${EndIf}
    $|    ReadRegStr $0 HKCU "\{key}" "InstallDir"
    $|    ReadRegStr $1 HKLM "\{key}" "InstallDir"
    $|    ${If} $0 == $ProtonInstallDirOverride
    $|    ${AndIf} $1 != $ProtonInstallDirOverride
    $|      Call MultiUser.InstallMode.CurrentUser
    $|    ${ElseIf} $1 == $ProtonInstallDirOverride
    $|    ${AndIf} $0 != $ProtonInstallDirOverride
    $|      Call MultiUser.InstallMode.AllUsers
    $|      ${If} $MultiUser.InstallMode != "AllUsers"
    $|        Abort "The update requires administrator privileges."
    $|      ${EndIf}
    $|    ${Else}
    $|      Abort "The update installation scope could not be determined."
    $|    ${EndIf}
    $|  ${EndIf}
    $|
  )
}
