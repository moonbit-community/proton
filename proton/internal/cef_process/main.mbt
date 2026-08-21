///|
fn main raise {
  match @native.execute_process(config=@native.RuntimeConfig::bundled()) {
    @native.ProcessResult::SubprocessHandled(exit_code) => @sys.exit(exit_code)
    @native.ProcessResult::MainProcess =>
      abort("cef_process must be launched by CEF")
  }
}
