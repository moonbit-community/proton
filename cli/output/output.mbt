///|
/// Writes one informational progress line to standard error, keeping standard
/// output reserved for command results.
pub async fn info(message : String) -> Unit noraise {
  write_stderr_line(message)
}

///|
/// Writes `message` followed by a newline to standard error. Write errors are
/// ignored so progress reporting and diagnostics never fail the command.
pub async fn write_stderr_line(message : String) -> Unit noraise {
  @stdio.stderr.write(message + "\n") catch {
    _ => ()
  }
}
