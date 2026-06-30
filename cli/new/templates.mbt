///|
let default_proton_version = "0.1.6"

///|
let default_async_version = "0.19.4"

///|
priv struct TemplateContext {
  title : String
  title_html : String
  title_mbt : String
  module_name : String
  module_mbt : String
  module_counter_import_mbt : String
  counter_extension_id_mbt : String
  width : Int
  height : Int
  proton_version : String
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
fn template_context(
  title : String,
  module_name : String,
  width : Int,
  height : Int,
) -> TemplateContext {
  {
    title,
    title_html: @template.escape_html(title),
    title_mbt: mbt_string(title),
    module_name,
    module_mbt: mbt_string(module_name),
    module_counter_import_mbt: mbt_string(module_name + "/extensions/counter"),
    counter_extension_id_mbt: mbt_string(module_name + "/counter"),
    width,
    height,
    proton_version: default_proton_version,
    async_version: default_async_version,
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
) -> Result[PlannedFile, String] {
  let vars = template_vars(context)
  match validate_template_placeholders(spec, vars) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let mut output = spec.template_source
  for item in vars {
    output = @template.replace(
      output,
      old="{{" + item.name + "}}",
      new=item.value,
    )
  }
  Ok({ path: spec.output_path, content: output })
}

///|
fn validate_template_placeholders(
  spec : TemplateSpec,
  vars : Array[TemplateVar],
) -> Result[Unit, String] {
  let mut probe = spec.template_source
  for item in vars {
    probe = @template.replace(probe, old="{{" + item.name + "}}", new="")
  }
  if probe.contains("{{") {
    Err(
      "template render failed for " +
      spec.template_name +
      ": unresolved placeholder",
    )
  } else {
    Ok(())
  }
}

///|
fn plan_project_files(
  title : String,
  module_name : String,
  width : Int,
  height : Int,
) -> Result[Array[PlannedFile], String] {
  let context = template_context(title, module_name, width, height)
  let files : Array[PlannedFile] = []
  for spec in template_specs() {
    match render_template(spec, context) {
      Ok(file) => files.push(file)
      Err(message) => return Err(message)
    }
  }
  Ok(files)
}

///|
fn template_specs() -> Array[TemplateSpec] {
  generated_template_specs()
}
