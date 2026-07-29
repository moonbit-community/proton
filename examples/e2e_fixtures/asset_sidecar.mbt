///|
struct AssetSidecarAddPayload {
  left : Int
  right : Int
} derive(FromJson)

///|
struct AssetSidecarReportPayload {
  report : String
} derive(FromJson)

///|
fn asset_sidecar_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/asset-sidecar-e2e",
      "add",
      [
        @proton_command.AppCommandApiDescriptor::new("add"),
        @proton_command.AppCommandApiDescriptor::new("addLater"),
        @proton_command.AppCommandApiDescriptor::new("reportProbe"),
      ],
      fn(context) raise {
        context.op("add", fn(payload : AssetSidecarAddPayload) {
          payload.left + payload.right
        })
        context.op_async("addLater", async fn(
          payload : AssetSidecarAddPayload,
        ) {
          @async.sleep(800)
          payload.left + payload.right
        })
        context.op("reportProbe", fn(payload : AssetSidecarReportPayload) {
          println("[asset-sidecar-e2e] " + payload.report)
          @mbfs.create_dir("target") catch {
            _ => ()
          }
          @mbfs.write_string_to_file(
            "target/asset-sidecar-e2e.probe.json",
            payload.report,
          ) catch {
            _ => ()
          }
        })
      },
    ),
  )
}
