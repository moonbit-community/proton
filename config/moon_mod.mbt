///|
fn parse_moon_mod_document(
  name : String,
  source : String,
) -> (Ast, Array[@basic.Report]) {
  let (ast, reports) = @moon_config.parse_moon_mod(name~, source)
  (convert_moon_config_ast(ast), reports)
}

///|
/// The moon.mod AST conversion is intentionally lossy: `Null` maps to
/// `Ast::Str("")`, `Float` maps to `Ast::Int`, and key locations track the
/// value position, because the module only reads version/description/license
/// style fields today. Add proper Float/Null Ast cases and key positions if
/// richer moon.mod values ever need validation.
fn convert_moon_config_ast(ast : @moon_config.Ast) -> Ast {
  match ast {
    Null(loc~) => Ast::Str("", loc)
    Bool(value, loc~) => Ast::Bool(value, loc)
    Str(value, loc~) => Ast::Str(decode_config_string(value), loc)
    Float(value, loc~) => Ast::Int(value, loc)
    Arr(items, loc~) => {
      let values : Array[Ast] = []
      for item in items {
        values.push(convert_moon_config_ast(item))
      }
      Ast::Arr(values, loc)
    }
    Obj(fields, loc~) => {
      let values : Array[ConfigField] = []
      for field in fields {
        let (key, value) = field
        values.push(ConfigField::{
          key,
          key_loc: value.loc(),
          value: convert_moon_config_ast(value),
        })
      }
      Ast::Obj(values, loc)
    }
  }
}
