///|
pub using @native {
  abi_version,
  execute_process,
  last_error_message,
  probe_runtime,
  runtime_info,
  runtime_info_json,
  screens,
  type NativeError,
  type BridgeDiagnostic,
  type BridgeLifecycleState,
  type Menu,
  type MenuBar,
  type MenuItem,
  type MenuItemRole,
  type MenuRole,
  type ProcessResult,
  type Runtime,
  type RuntimeConfig,
  type RuntimeEvent,
  type RuntimeInfo,
  type RuntimeLaunchInput,
  type ScreenInfo,
  type TitlebarStyle,
  type Window,
  type WindowConfig,
  type WindowMonitor,
  type WindowSizeHint,
  type WindowState,
}

///|
pub using @proton_command {
  type CommandContext,
  type CommandRegistrar,
  type PermissionScopeValidationError,
}

///|
pub type AppEntry = @manifest.AppEntry

///|
pub type PermissionGrant = @manifest.PermissionGrant

///|
pub type PermissionOrigin = @manifest.PermissionOrigin
