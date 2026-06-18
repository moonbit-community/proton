///|
struct AddReply {
  total : Int
  waited_ms : Int
} derive(ToJson)

///|
#lepus.event(name="addFinished")
struct AddFinished {
  total : Int
} derive(ToJson)

///|
#lepus.command(name="slowAdd")
async fn slow_add(
  context : @lepus.AppCommandExtensionContext,
  left : Int,
  right : Int,
  delay_ms : Int?,
) -> Result[AddReply, String] {
  let delay_ms = delay_ms.unwrap_or(250)
  @async.sleep(delay_ms)
  let total = left + right
  emit_add_finished(context, AddFinished::{ total, })
  Ok(AddReply::{ total, waited_ms: delay_ms })
}
