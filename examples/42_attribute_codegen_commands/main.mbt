///|
async fn main {
  let app = @proton.html(
    "Proton Attribute Codegen",
    resource,
    width=840,
    height=560,
    debug=true,
  ).capability(@proton_extension.capability(extension()))
  app.identifier("dev.proton.42-attribute-codegen-commands").run_or_abort()
}
