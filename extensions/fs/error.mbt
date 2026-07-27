///|
/// Failures produced by filesystem command validation and async I/O.
suberror FsError {
  UnsupportedCreateMode(value~ : String)
  UnsupportedSyncMode(value~ : String)
  ReadFailed(path~ : String, detail~ : String)
  WriteFailed(path~ : String, detail~ : String)
  ExistsFailed(path~ : String, detail~ : String)
  KindFailed(path~ : String, detail~ : String)
  SizeFailed(path~ : String, detail~ : String)
  ReadDirectoryFailed(path~ : String, detail~ : String)
  CreateDirectoryFailed(path~ : String, detail~ : String)
  RemoveFileFailed(path~ : String, detail~ : String)
  RemoveDirectoryFailed(path~ : String, detail~ : String)
  RenameFailed(old_path~ : String, new_path~ : String, detail~ : String)
  RealpathFailed(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
fn FsError::message(self : FsError) -> String {
  match self {
    UnsupportedCreateMode(value~) => "unsupported fs create_mode: " + value
    UnsupportedSyncMode(value~) => "unsupported fs sync mode: " + value
    ReadFailed(path~, detail~) => "failed to read file " + path + ": " + detail
    WriteFailed(path~, detail~) =>
      "failed to write file " + path + ": " + detail
    ExistsFailed(path~, detail~) =>
      "failed to inspect path existence " + path + ": " + detail
    KindFailed(path~, detail~) =>
      "failed to inspect path kind " + path + ": " + detail
    SizeFailed(path~, detail~) =>
      "failed to read file size " + path + ": " + detail
    ReadDirectoryFailed(path~, detail~) =>
      "failed to read directory " + path + ": " + detail
    CreateDirectoryFailed(path~, detail~) =>
      "failed to create directory " + path + ": " + detail
    RemoveFileFailed(path~, detail~) =>
      "failed to remove file " + path + ": " + detail
    RemoveDirectoryFailed(path~, detail~) =>
      "failed to remove directory " + path + ": " + detail
    RenameFailed(old_path~, new_path~, detail~) =>
      "failed to rename " + old_path + " to " + new_path + ": " + detail
    RealpathFailed(path~, detail~) =>
      "failed to resolve real path " + path + ": " + detail
  }
}

///|
impl Show for FsError with fn output(self, logger) {
  logger.write_string(self.message())
}
