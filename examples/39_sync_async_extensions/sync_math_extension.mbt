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
fn sync_math_extension() -> @app.AppCommandExtensionSpec {
  @app.AppCommandExtensionSpec::new(
    "examples/sync-math",
    "math",
    [@app.AppCommandApiDescriptor::new("double")],
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
  )
}
