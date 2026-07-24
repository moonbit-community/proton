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
fn sync_math_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/sync-math",
      "math",
      [@proton_command.AppCommandApiDescriptor::new("double")],
      fn(context) raise {
        context.op("double", fn(payload : DoublePayload) {
          DoubleReply::{
            value: payload.value,
            doubled: payload.value * 2,
            source: "sync command extension",
          }
        })
      },
    ),
  )
}
