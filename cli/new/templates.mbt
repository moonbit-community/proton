///|
let default_proton_version = "0.1.12"

///|
priv struct TemplateContext {
  title : String
  title_html : String
  title_mbt : String
  module_name : String
  module_mbt : String
  identifier_mbt : String
  module_counter_import_mbt : String
  counter_extension_id_mbt : String
  width : Int
  height : Int
  proton_version : String
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
  module_name : String,
  identifier : String,
  width : Int,
  height : Int,
) -> TemplateContext {
  {
    title,
    title_html: @template.escape_html(title),
    title_mbt: mbt_string(title),
    module_name,
    module_mbt: mbt_string(module_name),
    identifier_mbt: mbt_string(identifier),
    module_counter_import_mbt: mbt_string(module_name + "/extensions/counter"),
    counter_extension_id_mbt: mbt_string(module_name + "/counter"),
    width,
    height,
    proton_version: default_proton_version,
  }
}

///|
fn template_vars(context : TemplateContext) -> Array[TemplateVar] {
  [
    { name: "title", value: context.title },
    { name: "title_html", value: context.title_html },
    { name: "title_mbt", value: context.title_mbt },
    { name: "module_name", value: context.module_name },
    { name: "module_mbt", value: context.module_mbt },
    { name: "identifier_mbt", value: context.identifier_mbt },
    {
      name: "module_counter_import_mbt",
      value: context.module_counter_import_mbt,
    },
    {
      name: "counter_extension_id_mbt",
      value: context.counter_extension_id_mbt,
    },
    { name: "width", value: @template.render_value(context.width) },
    { name: "height", value: @template.render_value(context.height) },
    { name: "proton_version", value: context.proton_version },
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
  module_name : String,
  identifier : String,
  width : Int,
  height : Int,
) -> Array[PlannedFile] raise NewProjectTemplateError {
  let context = template_context(title, module_name, identifier, width, height)
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
