///|
// Test artifacts need an identity before Chromium selects its listening port.
let app_run_sequence : Ref[Int] = Ref(0)

///|
fn next_app_run_id() -> Int {
  app_run_sequence.val += 1
  app_run_sequence.val
}

///|
/// Reads only complete stderr lines, so a partial write cannot become a target.
fn announced_cdp_target(output : String) -> String? {
  let lines = output.split("\n").collect()
  for index in 0..<(lines.length() - 1) {
    let line = lines[index].trim()
    let prefix = "DevTools listening on ws://"
    guard line.has_prefix(prefix) else { continue }
    let address = line[prefix.length():]
    guard address.split("/devtools/browser/").collect() is [authority, browser] &&
      authority != "" &&
      browser != "" else {
      continue
    }
    return Some("http://" + authority.to_owned())
  }
  None
}

///|
async fn wait_for_app_cdp_target(
  app : SpawnedScenarioApp,
  timeout : Int,
) -> String {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    let output = @mbfs.read_file_to_string(app.output_path, encoding="utf8")
    if announced_cdp_target(output) is Some(target) {
      return target
    }
    if app_exit_code(app.process) is Some(code) {
      fail(
        "application exited before announcing CDP: code=" +
        code.to_string() +
        app_diagnostic_suffix(app),
      )
    }
    @async.sleep(25)
  }
  fail(
    "application did not announce CDP within " +
    timeout.to_string() +
    "ms" +
    app_diagnostic_suffix(app),
  )
}
