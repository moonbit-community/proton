///|
priv type FileHandle

///|
#borrow(path)
extern "C" fn open_file(path : Bytes) -> FileHandle = "proton_logging_open_file"

///|
#borrow(file)
extern "C" fn file_is_open(file : FileHandle) -> Bool = "proton_logging_file_is_open"

///|
#borrow(file, data)
extern "C" fn write_file(file : FileHandle, data : Bytes) -> Int = "proton_logging_write_file"

///|
#borrow(data)
extern "C" fn write_stderr(data : Bytes) -> Int = "proton_logging_write_stderr"

///|
extern "C" fn process_id() -> Int = "proton_logging_process_id"

///|
pub(all) suberror LoggingError {
  OpenFile(path~ : String)
  WriteFailed
} derive(Debug)

///|
pub extend LoggingError with Debug::{to_repr}

///|
priv struct StderrHandler {
  mut failed : Bool
}

///|
impl @xlog.Handler for StderrHandler with fn handle(
  self : StderrHandler,
  entry : @xlog.Entry,
) -> Unit raise {
  guard !self.failed else { raise LoggingError::WriteFailed }
  let data = @utf8.encode(entry.to_string() + "\n")
  guard write_stderr(data) == 0 else {
    self.failed = true
    raise LoggingError::WriteFailed
  }
}

///|
priv struct FileHandler {
  file : FileHandle
  mut failed : Bool
}

///|
fn FileHandler::FileHandler(path : String) -> FileHandler raise LoggingError {
  let file = open_file(@utf8.encode(path))
  guard file_is_open(file) else { raise OpenFile(path~) }
  FileHandler::{ file, failed: false, }
}

///|
impl @xlog.Handler for FileHandler with fn handle(
  self : FileHandler,
  entry : @xlog.Entry,
) -> Unit raise {
  guard !self.failed else { raise LoggingError::WriteFailed }
  let data = @utf8.encode(entry.to_string() + "\n")
  guard write_file(self.file, data) == 0 else {
    self.failed = true
    raise LoggingError::WriteFailed
  }
}

///|
pub(all) enum Output {
  Stderr
  File(String)
}

///|
/// Install process-wide output without changing filtering settings.
/// The global logger retains the handler after
/// this call returns; replacing it allows the file's GC finalizer to close it.
pub fn configure(output : Output) -> Unit raise LoggingError {
  let handler : &@xlog.Handler = match output {
    Stderr => (StderrHandler::{ failed: false, } : &@xlog.Handler)
    File(path) => (FileHandler(path) : &@xlog.Handler)
  }
  let logger = @xlog.global()
  logger.set_handler(handler)
}

///|
pub fn current_process_id() -> Int {
  process_id()
}
