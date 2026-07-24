///|
#proton.command(name="slowAdd")
async fn slow_add(left : Int, right : Int) -> Int {
  @async.sleep(1000)
  left + right
}
