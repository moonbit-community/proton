///|
pub(all) suberror NewProjectUsageError {
  Parse(message~ : String, usage_is_embedded~ : Bool)
} derive(Debug, Eq)

///|
/// Invalid values supplied while configuring a new project.
pub(all) suberror NewProjectInputError {
  InvalidPositiveInteger(field~ : String, value~ : String)
  EmptyTitle
  EmptyModuleName
  ModuleUsesBackslash
  ModuleHasBoundarySlash
  ModuleContainsSpace
  ModuleHasEmptySegment
  ModuleHasUnsupportedCharacter(character~ : Char)
  InvalidBundleIdentifier(identifier~ : String, reason~ : String)
  EmptyProjectDirectory
} derive(Debug, Eq)

///|
/// Conflicts or filesystem inspection failures at the requested target.
pub(all) suberror NewProjectTargetError {
  NotDirectory(path~ : String)
  ReadDirectory(path~ : String, detail~ : String)
  ContainsMoonModule(path~ : String)
  NotEmpty(path~ : String)
} derive(Debug, Eq)

///|
/// Internal failures while rendering the built-in project templates.
pub(all) suberror NewProjectTemplateError {
  UnresolvedPlaceholder(template~ : String)
} derive(Debug, Eq)

///|
/// Failures while materializing the planned project tree.
pub(all) suberror NewProjectWriteError {
  CreateDirectory(path~ : String, detail~ : String)
  WriteFile(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
/// Failures from optional external tools run after project creation.
pub(all) suberror NewProjectToolError {
  Start(tool~ : String, detail~ : String)
  Exit(tool~ : String, code~ : Int)
  MoonCheckFailed(code~ : Int, project~ : String)
} derive(Debug, Eq)

///|
pub fn NewProjectUsageError::message(self : NewProjectUsageError) -> String {
  match self {
    Parse(message~, ..) => message
  }
}

///|
pub fn NewProjectInputError::message(self : NewProjectInputError) -> String {
  match self {
    InvalidPositiveInteger(field~, value~) =>
      field + " must be a positive integer: " + value
    EmptyTitle => "app title must not be empty"
    EmptyModuleName => "module name must not be empty"
    ModuleUsesBackslash => "module name must use '/' instead of '\\'"
    ModuleHasBoundarySlash => "module name must not start or end with '/'"
    ModuleContainsSpace => "module name must not contain spaces"
    ModuleHasEmptySegment => "module name must not contain empty path segments"
    ModuleHasUnsupportedCharacter(character~) =>
      "module name contains unsupported character: " + character.to_string()
    InvalidBundleIdentifier(identifier~, reason~) =>
      "invalid bundle identifier " + identifier + ": " + reason
    EmptyProjectDirectory => "project directory must not be empty"
  }
}

///|
pub fn NewProjectTargetError::message(self : NewProjectTargetError) -> String {
  match self {
    NotDirectory(path~) => "target path is not a directory: " + path
    ReadDirectory(path~, detail~) =>
      "failed to read target directory " + path + ": " + detail
    ContainsMoonModule(path~) =>
      "target directory already contains moon.mod: " + path
    NotEmpty(path~) =>
      "target directory is not empty: " +
      path +
      "\n\nChoose a different directory:\n  proton_cli new " +
      path_basename(path) +
      "-2\n\nOr remove files manually and retry."
  }
}

///|
pub fn NewProjectTemplateError::message(
  self : NewProjectTemplateError,
) -> String {
  match self {
    UnresolvedPlaceholder(template~) =>
      "template render failed for " + template + ": unresolved placeholder"
  }
}

///|
pub fn NewProjectWriteError::message(self : NewProjectWriteError) -> String {
  match self {
    CreateDirectory(path~, detail~) =>
      "failed to create " + path + ": " + detail
    WriteFile(path~, detail~) => "failed to write " + path + ": " + detail
  }
}

///|
pub fn NewProjectToolError::message(self : NewProjectToolError) -> String {
  match self {
    Start(tool~, detail~) => "failed to run " + tool + ": " + detail
    Exit(tool~, code~) => tool + " failed with exit code " + code.to_string()
    MoonCheckFailed(code~, project~) =>
      "project was created, but moon check failed with exit code " +
      code.to_string() +
      "\n\nRetry with:\n  cd " +
      project +
      "\n  moon check --target native --diagnostic-limit 80"
  }
}

///|
impl Show for NewProjectUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for NewProjectInputError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for NewProjectTargetError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for NewProjectTemplateError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for NewProjectWriteError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for NewProjectToolError with fn output(self, logger) {
  logger.write_string(self.message())
}
