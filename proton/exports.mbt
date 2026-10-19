///|
pub using @proton_command {
  type CommandContext,
  type CommandWindow,
  type CommandRegistrar,
  type PermissionScopeValidationError,
}

///|
pub using @locale {type Locale, type LocaleParseError}

///|
pub type AppEntry = @manifest.AppEntry

///|
pub using @types {
  type AccessibilityMode,
  type AnimationSettings,
  type AppTaskMetric,
  type AppTaskType,
  type BridgeDiagnostic,
  type BrowserState,
  type CookieSameSite,
  type FindInPageResult,
  type JumpListCategory,
  type JumpListCategoryKind,
  type JumpListItem,
  type JumpListItemKind,
  type JumpListResult,
  type MediaAccessKind,
  type MediaAccessStatus,
  type MenuItemRole,
  type MenuRole,
  type ProgressBarMode,
  type RuntimeLaunchInput,
  type ScreenInfo,
  type ThumbarButtonFlag,
  type TitlebarStyle,
  type ViewState,
  type WindowMonitor,
  type WindowSizeHint,
  type WindowState,
  type WindowTheme,
  type WindowThemePreference,
}
