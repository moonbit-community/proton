///|
/// Invalid values supplied while configuring a new project.
pub(all) suberror NewProjectInputError {
  InvalidPositiveInteger(field~ : String, value~ : String)
  EmptyTitle
  InvalidAuthor(author~ : String, reason~ : String)
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
  CommandCodegen(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
/// Failures while materializing the planned project tree.
pub(all) suberror NewProjectWriteError {
  CreateDirectory(path~ : String, detail~ : String)
  WriteFile(path~ : String, detail~ : String)
  Commit(target~ : String, detail~ : String)
  Rollback(primary~ : String, detail~ : String)
} derive(Debug, Eq)

///|
/// Failures from optional external tools run before project publication.
pub(all) suberror NewProjectToolError {
  Start(tool~ : String, detail~ : String)
  Exit(tool~ : String, code~ : Int)
  RegistryDependenciesUnavailable(code~ : Int, project~ : String)
  MoonCheckFailed(code~ : Int, project~ : String)
} derive(Debug, Eq)

///|
pub fn NewProjectInputError::message(self : NewProjectInputError) -> String {
  match self {
    InvalidPositiveInteger(field~, value~) =>
      field + " must be a positive integer: " + value
    EmptyTitle => "app title must not be empty"
    InvalidAuthor(author~, reason~) =>
      "invalid module author " + author + ": " + reason
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
    CommandCodegen(path~, detail~) =>
      "scaffold command codegen failed for " + path + ": " + detail
  }
}

///|
pub fn NewProjectWriteError::message(self : NewProjectWriteError) -> String {
  match self {
    CreateDirectory(path~, detail~) =>
      "failed to create " + path + ": " + detail
    WriteFile(path~, detail~) => "failed to write " + path + ": " + detail
    Commit(target~, detail~) =>
      "failed to commit generated project at " + target + ": " + detail
    Rollback(primary~, detail~) =>
      "project generation failed: " +
      primary +
      "\ntransaction rollback also failed: " +
      detail
  }
}

///|
pub fn NewProjectToolError::message(self : NewProjectToolError) -> String {
  match self {
    Start(tool~, detail~) => "failed to run " + tool + ": " + detail
    Exit(tool~, code~) => tool + " failed with exit code " + code.to_string()
    RegistryDependenciesUnavailable(code~, project~) =>
      "moon check could not resolve the registry dependencies required by " +
      project +
      " (exit code " +
      code.to_string() +
      ").\n\nRequired Proton release chain:\n  " +
      scaffold_release_chain() +
      "\n\nThe project was rolled back. Install a Proton CLI release whose " +
      "template dependencies are available in the registry, then retry, " +
      "or retry with `proton_cli new --no-check` to skip validation."
    MoonCheckFailed(code~, project~) =>
      "moon check failed with exit code " +
      code.to_string() +
      " while validating " +
      project +
      "\nNo generated files were committed. " +
      "Retry with `proton_cli new --no-check` to skip validation."
  }
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
