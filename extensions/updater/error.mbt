///|
suberror UpdaterError {
  /// `download` was called without a check that found something.
  ///
  /// Not an argument error, because there is no argument: the page cannot say
  /// what to install, only whether to install what the host already found.
  NothingOffered
} derive(Debug)

///|
pub extend UpdaterError with Debug::{to_repr}

///|
pub extend UpdaterError with Show::{to_string, output}

///|
impl Show for UpdaterError with fn output(self, logger) {
  match self {
    NothingOffered =>
      logger.write_string(
        "no update has been offered; call check() and act on its result",
      )
  }
}
