///|
fn parse_moon_mod_document(
  name : String,
  source : String,
) -> (Ast, Array[@basic.Report]) {
  let (ast, reports) = @moon_config.parse_moon_mod(name~, source)
  (convert_moon_config_ast(ast), convert_moon_config_reports(reports))
}

///|
fn convert_moon_config_ast(ast : @moon_config.Ast) -> Ast {
  match ast {
    Null(loc~) => Ast::Str("", convert_moon_config_loc(loc))
    Bool(value, loc~) => Ast::Bool(value, convert_moon_config_loc(loc))
    Str(value, loc~) =>
      Ast::Str(decode_config_string(value), convert_moon_config_loc(loc))
    Float(value, loc~) => Ast::Int(value, convert_moon_config_loc(loc))
    Arr(items, loc~) => {
      let values : Array[Ast] = []
      for item in items {
        values.push(convert_moon_config_ast(item))
      }
      Ast::Arr(values, convert_moon_config_loc(loc))
    }
    Obj(fields, loc~) => {
      let values : Array[ConfigField] = []
      for field in fields {
        let (key, value) = field
        values.push(ConfigField::{
          key,
          key_loc: convert_moon_config_loc(value.loc()),
          value: convert_moon_config_ast(value),
        })
      }
      Ast::Obj(values, convert_moon_config_loc(loc))
    }
  }
}

///|
fn convert_moon_config_reports(
  reports : Array[@parser_basic.Report],
) -> Array[@basic.Report] {
  let out : Array[@basic.Report] = []
  for report in reports {
    out.push(@basic.Report::{
      loc: convert_moon_config_loc(report.loc),
      msg: report.msg,
    })
  }
  out
}

///|
fn convert_moon_config_loc(loc : @parser_basic.Location) -> @basic.Location {
  @basic.Location::{
    start: convert_moon_config_pos(loc.start),
    end: convert_moon_config_pos(loc.end),
  }
}

///|
fn convert_moon_config_pos(pos : @parser_basic.Position) -> @basic.Position {
  @basic.Position::{
    fname: pos.fname,
    lnum: pos.lnum,
    bol: pos.bol,
    cnum: pos.cnum,
  }
}
