///|
test "file handler writes through the configured xlog root" {
  let path = ".proton-logging-test-" + current_process_id().to_string() + ".log"
  defer (@fs.remove_file(path) catch { _ => () })
  let logging = RuntimeLogging(
    Output::File(path),
    @xlog.Config(level=@xlog.Warn),
  )
  @xlog.warn(category="proton.test") <? { "message": "handler probe" }
  logging.close()
  let contents = @fs.read_file_to_string(path)
  assert_true(contents.contains("category=proton.test"))
  assert_true(contents.contains("message=\"handler probe\""))
}
