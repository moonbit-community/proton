///|
#proton.command(name="add")
fn add(left : Int, right : Int) -> Int {
  left + right
}

///|
struct ProbeReply {
  ok : Bool
} derive(ToJson)

///|
#proton.command(name="reportProbe")
fn report_probe(report : String) -> ProbeReply {
  println("[asset-sidecar] " + report)
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.write_string_to_file("target/asset-sidecar.probe.json", report) catch {
    _ => ()
  }
  ProbeReply::{ ok: true }
}
