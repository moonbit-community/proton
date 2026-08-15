///|
/// Failures while adapting a framework extension to the app command runtime.
pub(all) suberror ExtensionAdapterError {
  TypedSpecInvalid(extension_id~ : String, detail~ : String)
} derive(Debug)

///|
pub extend ExtensionAdapterError with Debug::{to_repr}

///|
pub extend ExtensionAdapterError with Show::{to_string, output}

///|
pub fn ExtensionAdapterError::message(self : ExtensionAdapterError) -> String {
  match self {
    TypedSpecInvalid(extension_id~, detail~) =>
      "invalid typed extension " + extension_id + ": " + detail
  }
}

///|
impl Show for ExtensionAdapterError with fn output(self, logger) {
  logger.write_string(self.message())
}
