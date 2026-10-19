///|
/// Controls whether web content stays below or extends beneath the titlebar.
pub(all) enum TitlebarStyle {
  Default
  Overlay
} derive(Debug, Eq)

///|
pub extend TitlebarStyle with Eq::{not_equal, equal}

///|
pub extend TitlebarStyle with Debug::{to_repr}

///|
/// Controls how Proton chooses the native window chrome theme.
pub(all) enum WindowThemePreference {
  System
  Light
  Dark
} derive(Debug, Eq)

///|
pub extend WindowThemePreference with Eq::{not_equal, equal}

///|
pub extend WindowThemePreference with Debug::{to_repr}

///|
/// Controls how configured window dimensions constrain native resizing.
pub(all) enum WindowSizeHint {
  Unconstrained
  Fixed
  Min
  Max
} derive(Debug, Eq)

///|
pub extend WindowSizeHint with Eq::{not_equal, equal}

///|
pub extend WindowSizeHint with Debug::{to_repr}

///|
/// Explicit progress states for `WindowHandle::set_progress_bar`, mirroring
/// Electron's `mode` option. Only Windows renders the explicit states; macOS
/// and Linux derive the indicator from the progress value alone.
pub(all) enum ProgressBarMode {
  /// Derives the state from the value: a negative value clears the indicator,
  /// `0.0` through `1.0` is determinate, and values above `1.0` are
  /// indeterminate.
  Automatic
  Normal
  Indeterminate
  Error
  Paused
  /// Removes the indicator without changing the last reported value.
  Cleared
} derive(Debug, Eq)

///|
pub extend ProgressBarMode with Eq::{not_equal, equal}

///|
pub extend ProgressBarMode with Debug::{to_repr}

///|
/// Taskbar thumbnail-toolbar button flags, mirroring Electron's `flags` array.
/// A button is enabled unless `Disabled` or `NonInteractive` is present.
pub(all) enum ThumbarButtonFlag {
  Disabled
  DismissOnClick
  NoBackground
  Hidden
  NonInteractive
} derive(Debug, Eq)

///|
pub extend ThumbarButtonFlag with Eq::{not_equal, equal}

///|
pub extend ThumbarButtonFlag with Debug::{to_repr}

///|
/// The kind of a jump list item, mirroring Electron's `type` property.
pub(all) enum JumpListItemKind {
  /// Launches `path` with `arguments`, shown as `title`.
  Task
  /// Separates items in the standard Tasks category; other categories reject
  /// it.
  Separator
  /// Opens `path` with the application that registered that file type.
  File
} derive(Debug, Eq)

///|
pub extend JumpListItemKind with Eq::{not_equal, equal}

///|
pub extend JumpListItemKind with Debug::{to_repr}

///|
/// The kind of a jump list category, mirroring Electron's `type` property.
pub(all) enum JumpListCategoryKind {
  /// The standard Tasks category, always shown at the bottom.
  Tasks
  /// An application-named category holding tasks and file links.
  Custom
  /// The Windows-managed recent files category.
  Recent
  /// The Windows-managed frequently used category.
  Frequent
} derive(Debug, Eq)

///|
pub extend JumpListCategoryKind with Eq::{not_equal, equal}

///|
pub extend JumpListCategoryKind with Debug::{to_repr}

///|
/// One item inside a custom jump list category.
///
/// Empty strings mean "not set", which is how Electron treats omitted
/// properties: a task needs `path` and `title`, a file link needs `path`, and a
/// separator needs neither.
pub(all) struct JumpListItem {
  kind : JumpListItemKind
  path : String
  arguments : String
  title : String
  description : String
  icon_path : String
  icon_index : Int32
  working_directory : String
}

///|
/// One category of the custom jump list, mirroring Electron's
/// `JumpListCategory`.
pub(all) struct JumpListCategory {
  kind : JumpListCategoryKind
  /// Required when `kind` is `Custom`, ignored otherwise.
  name : String
  /// Used by `Tasks` and `Custom`; `Recent` and `Frequent` are managed by
  /// Windows.
  items : Array[JumpListItem]
}

///|
/// The result of a jump list update, mirroring the strings Electron returns
/// from `setJumpList`.
pub(all) enum JumpListResult {
  /// Nothing went wrong.
  Ok
  /// One or more categories or items failed.
  Error
  /// A separator was added to a category other than Tasks.
  InvalidSeparator
  /// A file link was added for a file type the application does not handle.
  FileTypeRegistrationError
  /// Windows denied custom categories through privacy or group policy.
  CustomCategoryAccessDenied
  /// The platform has no jump list. Proton reports this instead of Electron's
  /// undefined method on macOS and Linux.
  Unsupported
} derive(Debug, Eq)

///|
pub extend JumpListResult with Eq::{not_equal, equal}

///|
pub extend JumpListResult with Debug::{to_repr}

///|
/// A standard top-level application menu role.
pub(all) enum MenuRole {
  Application
  File
  Edit
  View
  Window
  Help
} derive(Debug, Eq)

///|
pub extend MenuRole with Eq::{not_equal, equal}

///|
pub extend MenuRole with Debug::{to_repr}

///|
/// A standard native menu action.
pub(all) enum MenuItemRole {
  Quit
  Hide
  HideOthers
  ShowAll
  Close
  Minimize
  Zoom
  Undo
  Redo
  Cut
  Copy
  Paste
  SelectAll
} derive(Debug, Eq)

///|
pub extend MenuItemRole with Eq::{not_equal, equal}

///|
pub extend MenuItemRole with Debug::{to_repr}

///|
/// SameSite policy for a browser cookie.
pub(all) enum CookieSameSite {
  Unspecified
  NoRestriction
  Lax
  Strict
} derive(Debug, Eq)

///|
pub extend CookieSameSite with Eq::{not_equal, equal}

///|
pub extend CookieSameSite with Debug::{to_repr}

///|
/// Controls when Proton enables the browser accessibility tree.
pub(all) enum AccessibilityMode {
  Automatic
  AlwaysEnabled
} derive(Eq, Debug)

///|
pub extend AccessibilityMode with Eq::{not_equal, equal}

///|
pub extend AccessibilityMode with Debug::{to_repr}

///|
pub extend TitlebarStyle with Show::{to_string, output}

///|
pub impl Show for TitlebarStyle with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Overlay => logger.write_string("Overlay")
  }
}

///|
pub extend WindowThemePreference with Show::{to_string, output}

///|
pub impl Show for WindowThemePreference with fn output(self, logger) {
  match self {
    System => logger.write_string("System")
    Light => logger.write_string("Light")
    Dark => logger.write_string("Dark")
  }
}
