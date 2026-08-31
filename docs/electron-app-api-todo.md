# Electron `app` API Compatibility TODO

Reference: <https://www.electronjs.org/docs/latest/api/app>

This checklist tracks Electron `app` behavior against Proton's public root
facade. A checked item means that application developers can achieve the same
user-visible behavior through a supported Proton API; the API shape does not
need to copy Electron's JavaScript singleton.

Status markers:

- `[x]` supported
- `[~]` partially supported or intentionally modeled differently
- `[ ]` not implemented
- `[!]` blocked by an architectural or upstream dependency

## P0: Application Metadata And Paths

- [x] `getName()` / `name`: read managed development and packaged product name
- [x] `getVersion()`: read managed development and packaged application version
- [x] `isPackaged`: distinguish packaged applications from development/direct runs
- [x] `getAppPath()`: return the application resource root
- [x] `getPath('home')`
- [x] `getPath('appData')`
- [~] `getPath('userData')`: uses the stable application identifier and Proton's
  native-data root instead of the display name and configuration root
- [~] `getPath('sessionData')`: resolves Proton's dedicated browser-data
  subdirectory rather than aliasing `userData`
- [x] `getPath('temp')`
- [x] `getPath('exe')`
- [~] `getPath('logs')`: resolves Proton's structured logging directory, which
  intentionally follows platform logging conventions
- [ ] `getPath('assets')` (Windows and Linux)
- [ ] `getPath('module')`
- [ ] `getPath('desktop' | 'documents' | 'downloads' | 'music' | 'pictures' | 'videos')`
- [ ] `getPath('recent')` (Windows)
- [ ] `getPath('crashDumps')`
- [ ] `setPath(name, path)`
- [ ] `setAppLogsPath(path)`
- [ ] `getFileIcon(path, options)`
- [ ] `setName(name)`
- [ ] `setDesktopName(name)` (Linux)
- [ ] `commandLine`
- [ ] `userAgentFallback`
- [ ] `runningUnderARM64Translation`

The first implementation group covers managed name/version, packaged state,
application root, and the high-frequency cross-platform path subset through
`logs`. Media folders, Windows recent documents, crash dumps, and mutable path
overrides remain separate work because they need additional platform policy.

## P0: Lifecycle And Process Control

- [x] `quit()` through `ApplicationContext::quit`
- [~] `ready` / `whenReady()` through application and window lifecycle hooks
- [~] `window-all-closed` through `LastWindowClosedPolicy`
- [~] `open-file`, `open-url`, and `activate` through typed `RuntimeLaunchInput`
- [~] `second-instance` through declarative single-instance activation; arbitrary
  `argv`, working directory, and `additionalData` are not exposed
- [~] `requestSingleInstanceLock` through startup-only `App::single_instance`;
  runtime acquisition and `additionalData` are not exposed
- [ ] `hasSingleInstanceLock`
- [ ] `releaseSingleInstanceLock`
- [~] `browser-window-focus` / `browser-window-blur` through `WindowEvent`
- [ ] `will-finish-launching`
- [ ] cancellable `before-quit`
- [ ] `will-quit`
- [ ] `quit` with exit code
- [ ] `exit(exitCode)`
- [ ] `relaunch(options)`
- [ ] `isReady()`
- [ ] application-level `focus(options)`
- [ ] application-level `hide()` / `show()` / `isHidden()` (macOS)
- [ ] application-level `isActive()` (macOS)
- [ ] `browser-window-created`
- [ ] `web-contents-created`
- [ ] `render-process-gone`
- [ ] `child-process-gone`
- [ ] `session-created`
- [ ] `new-window-for-tab` (macOS)

## P0: Protocols And Desktop Integration

- [~] URL schemes and document types can be declared for packaging and their
  activations are delivered through `RuntimeLaunchInput`
- [ ] `setAsDefaultProtocolClient`
- [ ] `removeAsDefaultProtocolClient`
- [ ] `isDefaultProtocolClient`
- [ ] `getApplicationNameForProtocol`
- [ ] `getApplicationInfoForProtocol`
- [ ] `addRecentDocument`
- [ ] `clearRecentDocuments`
- [ ] `getRecentDocuments`
- [~] `setLoginItemSettings` / `getLoginItemSettings` have a narrower equivalent
  in `proton_auto_launch`
- [ ] `setUserTasks` (Windows)
- [ ] `getJumpListSettings` / `setJumpList` (Windows)
- [ ] `setAppUserModelId` (Windows)
- [ ] `setToastActivatorCLSID` / `toastActivatorCLSID` (Windows)
- [ ] `showAboutPanel` / `setAboutPanelOptions`
- [ ] `isEmojiPanelSupported` / `showEmojiPanel`

## P1: Menu, Badge, Dock, And Activation

- [x] application and window menus through `App::menu` and
  `WindowHandle::set_menu`
- [~] `applicationMenu`: application menus can be configured but not queried
- [~] `setBadgeCount` through `notification_set_badge_count`; no getter
- [ ] `getBadgeCount` / `badgeCount`
- [ ] `dock` API (macOS)
- [ ] `did-become-active` / `did-resign-active` (macOS)
- [ ] `setActivationPolicy` (macOS)
- [ ] `isInApplicationsFolder` / `moveToApplicationsFolder` (macOS)
- [ ] `isUnityRunning` (Linux)

## P1: Networking, Certificates, And Authentication

- [x] `certificate-error` through `App::on_certificate_error`
- [ ] `select-client-certificate`
- [ ] `login`
- [ ] `importCertificate` (Linux)
- [ ] `setClientCertRequestPasswordHandler` (Linux)
- [ ] `configureHostResolver`
- [ ] `setProxy` / `resolveProxy`
- [ ] `configureWebAuthn` (macOS)

Proxy configuration should be owned by `SessionHandle` unless an app-wide
startup default is also required.

## P1: Hardware, Diagnostics, And Accessibility

- [ ] `disableHardwareAcceleration`
- [ ] `isHardwareAccelerationEnabled`
- [ ] `disableDomainBlockingFor3DAPIs`
- [ ] `getAppMetrics`
- [ ] `getGPUFeatureStatus`
- [ ] `getGPUInfo`
- [ ] `gpu-info-update`
- [ ] `isAccessibilitySupportEnabled` / `accessibilitySupportEnabled`
- [ ] `setAccessibilitySupportEnabled`
- [ ] `getAccessibilitySupportFeatures`
- [ ] `setAccessibilitySupportFeatures`
- [ ] `accessibility-support-changed`

## P1: Locale

- [~] `getLocale()`: the immutable application locale is available from
  lifecycle contexts and can be selected with `App::locale`
- [~] `getLocaleCountryCode()`: available through the selected locale's region
- [~] `getSystemLocale()`: system locale discovery is exposed as an ordered
  language list rather than a single locale
- [x] `getPreferredSystemLanguages()` through `system_preferred_languages`

## P2: macOS Continuity And Security

- [ ] `setUserActivity`
- [ ] `getCurrentActivityType`
- [ ] `invalidateCurrentActivity`
- [ ] `resignCurrentActivity`
- [ ] `updateCurrentActivity`
- [ ] `continue-activity`
- [ ] `will-continue-activity`
- [ ] `continue-activity-error`
- [ ] `activity-was-continued`
- [ ] `update-activity-state`
- [ ] `startAccessingSecurityScopedResource`
- [ ] `isSecureKeyboardEntryEnabled`
- [ ] `setSecureKeyboardEntryEnabled`

## Architectural Work

- [!] `enableSandbox`: Proton currently starts CEF without its sandbox. Enabling
  it requires subprocess, packaging, entitlement, and three-platform validation.
- [!] Full Chrome extension lifecycle: current CEF removed the Alloy extension
  management API. Startup-only extension loading needs a feasibility spike and
  must not be presented as Electron `Session.extensions` parity.
