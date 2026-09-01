///|
extern "C" fn link_anchor() = "proton_cef_process_link_anchor"

///|
fn main raise {
  link_anchor()
  match @native.execute_process(config=@native.RuntimeConfig::bundled()) {
    @native.ProcessResult::SubprocessHandled(exit_code) => @sys.exit(exit_code)
    @native.ProcessResult::MainProcess =>
      abort("cef_process must be launched by CEF")
  }
}
