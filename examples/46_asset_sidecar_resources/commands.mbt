///|
#proton.command(name="add")
fn add(left : Int, right : Int) -> Int {
  left + right
}

///|
#proton.command(name="addLater")
async fn add_later(left : Int, right : Int) -> Result[Int, String] {
  @async.sleep(800)
  Ok(left + right)
}

///|
#proton.command(name="reportProbe")
fn report_probe(report : String) -> Unit {
  println("[asset-sidecar] " + report)
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.write_string_to_file("target/asset-sidecar.probe.json", report) catch {
    _ => ()
  }
}
