///|
struct DoublePayload {
  value : Int
} derive(FromJson)

///|
struct DoubleReply {
  value : Int
  doubled : Int
  source : String
} derive(ToJson)

///|
fn sync_math_extension() -> @lepus_extension.Extension {
  @lepus_extension.from_command_spec(
    @lepus_command.AppCommandExtensionSpec::new(
      "examples/sync-math",
      "math",
      [@lepus_command.AppCommandApiDescriptor::new("double")],
      fn(context) {
        context.op("double", fn(payload : DoublePayload) {
          DoubleReply::{
            value: payload.value,
            doubled: payload.value * 2,
            source: "sync command extension",
          }
        })
        Ok(())
      },
    ),
  )
}
