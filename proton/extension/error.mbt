///|
/// Failures while adapting a framework extension to the app command runtime.
pub(all) suberror ExtensionAdapterError {
  DescriptorBuildFailed(extension_id~ : String, detail~ : String)
  DescriptorInstallFailed(extension_id~ : String, detail~ : String)
} derive(Debug)

///|
pub fn ExtensionAdapterError::message(self : ExtensionAdapterError) -> String {
  match self {
    DescriptorBuildFailed(extension_id~, detail~) =>
      "failed to build extension descriptor for " + extension_id + ": " + detail
    DescriptorInstallFailed(extension_id~, detail~) =>
      "failed to inspect extension descriptor for " +
      extension_id +
      ": " +
      detail
  }
}

///|
impl Show for ExtensionAdapterError with fn output(self, logger) {
  logger.write_string(self.message())
}
