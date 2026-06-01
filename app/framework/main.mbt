///|
fn main {
  match @lepus_app.run_framework_process_from_cli() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
