///|
let default_proton_version = "0.1.17"

///|
let default_proton_codegen_version = "0.1.17"

///|
let default_proton_cli_version = "0.1.17"

///|
let default_proton_contract_version = "0.1.17"

///|
let default_proton_client_version = "0.1.17"

///|
let default_proton_rabbita_version = "0.1.17"

///|
let default_rabbita_version = "0.14.1"

///|
let default_warren_version = "0.2.4"

///|
/// Scaffolded backends need this directly: `async fn main` is only available to
/// a package that imports `moonbitlang/async`.
let default_async_version = "0.20.3"

///|
fn scaffold_release_chain() -> String {
  "moonbit-community/proton_contract@" +
  default_proton_contract_version +
  "\n  moonbit-community/proton_codegen@" +
  default_proton_codegen_version +
  "\n  moonbit-community/proton_client@" +
  default_proton_client_version +
  "\n  moonbit-community/proton_rabbita@" +
  default_proton_rabbita_version +
  "\n  moonbit-community/proton@" +
  default_proton_version +
  "\n  moonbit-community/proton_cli@" +
  default_proton_cli_version
}

///|
priv struct TemplateContext {
  title : String
  title_html : String
  title_mbt : String
  author : String
  project_name : String
  shared_module : String
  frontend_module : String
  backend_module : String
  identifier : String
  identifier_mbt : String
  width : Int
  height : Int
  proton_version : String
  proton_codegen_version : String
  proton_cli_version : String
  proton_contract_version : String
  proton_client_version : String
  proton_rabbita_version : String
  rabbita_version : String
  warren_version : String
  async_version : String
}

///|
priv struct TemplateVar {
  name : String
  value : String
}

///|
priv struct TemplateSpec {
  output_path : String
  template_name : String
  template_source : String
}

///|
struct PlannedFile {
  path : String
  content : String
} derive(Debug, Eq)

///|
pub extend PlannedFile with Eq::{not_equal, equal}

///|
pub extend PlannedFile with Debug::{to_repr}

///|
fn template_context(
  title : String,
  author : String,
  project_name : String,
  identifier : String,
  width : Int,
  height : Int,
) -> TemplateContext {
  let module_prefix = author + "/" + project_name
  {
    title,
    title_html: escape_html(title),
    title_mbt: mbt_string(title),
    author,
    project_name,
    shared_module: module_prefix + "_shared",
    frontend_module: module_prefix + "_frontend",
    backend_module: module_prefix + "_backend",
    identifier,
    identifier_mbt: mbt_string(identifier),
    width,
    height,
    proton_version: default_proton_version,
    proton_codegen_version: default_proton_codegen_version,
    proton_cli_version: default_proton_cli_version,
    proton_contract_version: default_proton_contract_version,
    proton_client_version: default_proton_client_version,
    proton_rabbita_version: default_proton_rabbita_version,
    rabbita_version: default_rabbita_version,
    warren_version: default_warren_version,
    async_version: default_async_version,
  }
}

///|
fn template_vars(context : TemplateContext) -> Array[TemplateVar] {
  [
    { name: "title", value: context.title },
    { name: "title_html", value: context.title_html },
    { name: "title_mbt", value: context.title_mbt },
    { name: "author", value: context.author },
    { name: "project_name", value: context.project_name },
    { name: "shared_module", value: context.shared_module },
    { name: "frontend_module", value: context.frontend_module },
    { name: "backend_module", value: context.backend_module },
    { name: "identifier_mbt", value: context.identifier_mbt },
    { name: "width", value: context.width.to_string() },
    { name: "height", value: context.height.to_string() },
    { name: "proton_version", value: context.proton_version },
    { name: "proton_codegen_version", value: context.proton_codegen_version },
    { name: "proton_cli_version", value: context.proton_cli_version },
    { name: "proton_contract_version", value: context.proton_contract_version },
    { name: "proton_client_version", value: context.proton_client_version },
    { name: "proton_rabbita_version", value: context.proton_rabbita_version },
    { name: "rabbita_version", value: context.rabbita_version },
    { name: "warren_version", value: context.warren_version },
    { name: "async_version", value: context.async_version },
  ]
}

///|
fn mbt_string(value : String) -> String {
  let out = StringBuilder::new()
  out.write_char('"')
  for ch in value {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(ch)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn render_template(
  spec : TemplateSpec,
  context : TemplateContext,
) -> PlannedFile raise NewProjectTemplateError {
  let vars = template_vars(context)
  validate_template_placeholders(spec, vars)
  let mut output = spec.template_source
  for item in vars {
    output = output.replace_all(old="{{" + item.name + "}}", new=item.value)
  }
  { path: spec.output_path, content: output }
}

///|
fn validate_template_placeholders(
  spec : TemplateSpec,
  vars : Array[TemplateVar],
) -> Unit raise NewProjectTemplateError {
  let mut probe = spec.template_source
  for item in vars {
    probe = probe.replace_all(old="{{" + item.name + "}}", new="")
  }
  if probe.contains("{{") {
    raise UnresolvedPlaceholder(template=spec.template_name)
  }
}

///|
fn plan_project_files(
  title : String,
  author : String,
  project_name : String,
  identifier : String,
  width : Int,
  height : Int,
) -> Array[PlannedFile] raise NewProjectTemplateError {
  let context = template_context(
    title, author, project_name, identifier, width, height,
  )
  let files : Array[PlannedFile] = []
  for spec in template_specs() {
    files.push(render_template(spec, context))
  }
  files.push(project_config_file(context))
  files
}

///|
fn project_config_file(context : TemplateContext) -> PlannedFile {
  let config : Json = {
    "product_name": context.title,
    "identifier": context.identifier,
    "single_instance": true,
    "window": {
      "title": context.title,
      "width": context.width,
      "height": context.height,
      "size_hint": "none",
    },
    "backend": { "path": "backend", "package": "app" },
    "frontend": {
      "path": "frontend",
      "dev_url": "http://127.0.0.1:4300",
      "before_dev": "moonx --target native moonbit-community/warren@" +
      context.warren_version +
      " dev --direct --port 4300",
      "before_build": "moonx --target native moonbit-community/warren@" +
      context.warren_version +
      " build",
      "dist": "dist",
    },
    "entry": { "kind": "asset", "value": "frontend/dist/index.html" },
    "permissions": [{ "window": "main", "origin": "entry", "extension": "app" }],
    "debug": true,
    "bundle": { "active": true, "targets": ["app", "zip"], "output": "dist" },
  }
  { path: "proton.project.json", content: config.stringify(indent=2) + "\n" }
}

///|
fn template_specs() -> Array[TemplateSpec] {
  generated_template_specs()
}
