///|
async fn evaluate_bool(
  page : @page.Page,
  expression : String,
  await_promise : Bool,
) -> Bool {
  page.evaluate(expression, await_promise~) is True
}

///|
async fn evaluate_json(
  page : @page.Page,
  expression : String,
  await_promise : Bool,
) -> Json {
  page.evaluate(expression, await_promise~)
}

///|
async fn reload_page_and_wait(
  page : @page.Page,
  expression : String,
  description : String,
  timeout : Int,
) -> Unit {
  let navigation = page.reload()
  ignore(
    run_e2e_operation_with_timeout(
      timeout,
      "main-frame execution context after reload",
      () => navigation.wait_for_context(),
    ),
  )
  wait_for_cdp_expression(page, expression, description, timeout)
}
