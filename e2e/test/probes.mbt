///|
fn scenario_probe_expression(name : String) -> String {
  match basic_probe_expression(name) {
    Some(expression) => expression
    None =>
      match app_probe_expression(name) {
        Some(expression) => expression
        None =>
          match command_probe_expression(name) {
            Some(expression) => expression
            None => "document.readyState !== 'loading'"
          }
      }
  }
}
