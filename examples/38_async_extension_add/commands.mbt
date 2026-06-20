///|
#proton.command(name="slowAdd")
async fn slow_add(left : Int, right : Int) -> Result[Int, String] {
  @async.sleep(1000)
  Ok(left + right)
}
