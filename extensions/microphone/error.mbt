///|
/// Invalid microphone capture configuration supplied by JavaScript.
suberror MicrophoneError {
  UnknownSampleFormat(format~ : String)
} derive(Debug, Eq)

///|
fn MicrophoneError::message(self : MicrophoneError) -> String {
  match self {
    UnknownSampleFormat(format~) =>
      "unknown microphone sample format: " + format
  }
}

///|
impl Show for MicrophoneError with fn output(self, logger) {
  logger.write_string(self.message())
}
