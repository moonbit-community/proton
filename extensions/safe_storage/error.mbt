///|
pub(all) suberror SafeStorageError {
  OperationFailed(detail~ : String)
} derive(Debug, Eq)

///|
pub fn SafeStorageError::message(self : SafeStorageError) -> String {
  match self {
    OperationFailed(detail~) => "safe storage operation failed: " + detail
  }
}
