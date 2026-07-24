///|
/// Invalid microphone capture configuration supplied by JavaScript.
suberror MicrophoneConfigError {
  UnknownSampleFormat(format~ : String)
} derive(Debug, Eq)

///|
fn MicrophoneConfigError::message(self : MicrophoneConfigError) -> String {
  match self {
    UnknownSampleFormat(format~) =>
      "unknown microphone sample format: " + format
  }
}

///|
impl Show for MicrophoneConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}
