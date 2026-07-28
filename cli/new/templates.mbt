///|
let default_proton_version = "0.1.12"

///|
let default_proton_cli_version = "0.1.9"

///|
let default_proton_rabbita_version = "0.1.0"

///|
let default_rabbita_version = "0.12.4"

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
  identifier_mbt : String
  width : Int
  height : Int
  proton_version : String
  proton_cli_version : String
  proton_rabbita_version : String
  rabbita_version : String
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
    title_html: @template.escape_html(title),
    title_mbt: mbt_string(title),
    author,
    project_name,
    shared_module: module_prefix + "_shared",
    frontend_module: module_prefix + "_frontend",
    backend_module: module_prefix + "_backend",
    identifier_mbt: mbt_string(identifier),
    width,
    height,
    proton_version: default_proton_version,
    proton_cli_version: default_proton_cli_version,
    proton_rabbita_version: default_proton_rabbita_version,
    rabbita_version: default_rabbita_version,
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
    { name: "width", value: @template.render_value(context.width) },
    { name: "height", value: @template.render_value(context.height) },
    { name: "proton_version", value: context.proton_version },
    { name: "proton_cli_version", value: context.proton_cli_version },
    { name: "proton_rabbita_version", value: context.proton_rabbita_version },
    { name: "rabbita_version", value: context.rabbita_version },
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
    output = @template.replace(
      output,
      old="{{" + item.name + "}}",
      new=item.value,
    )
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
    probe = @template.replace(probe, old="{{" + item.name + "}}", new="")
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
  files
}

///|
fn template_specs() -> Array[TemplateSpec] {
  generated_template_specs()
}
