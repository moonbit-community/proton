///|
#derive(Debug, Eq)
pub(all) suberror SafeStorageError {
  OperationFailed(detail~ : String)
}

///|
pub extend SafeStorageError with Debug::{to_repr}

///|
pub extend SafeStorageError with Eq::{not_equal, equal}

///|
pub fn SafeStorageError::message(self : SafeStorageError) -> String {
  match self {
    OperationFailed(detail~) => "safe storage operation failed: " + detail
  }
}
