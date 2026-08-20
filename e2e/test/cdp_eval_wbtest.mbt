///|
test "missing default execution context is transient while polling readiness" {
  assert_true(
    is_transient_execution_context_error(
      @client.BrowserError::CommandFailed(
        -32000, "Cannot find default execution context",
      ),
    ),
  )
  assert_false(
    is_transient_execution_context_error(
      @client.BrowserError::CommandFailed(
        -32000, "Execution context was destroyed.",
      ),
    ),
  )
  assert_false(
    is_transient_execution_context_error(
      @client.BrowserError::CommandFailed(-32601, "Method not found"),
    ),
  )
}
