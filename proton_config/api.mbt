///|
pub fn parse_moon_proton(
  name? : String = "moon.proton",
  source : String,
) -> (Ast, Array[@basic.Report]) {
  parse_config_document(name, source)
}

///|
pub fn parse_moon_ext(
  name? : String = "moon.ext",
  source : String,
) -> (Ast, Array[@basic.Report]) {
  parse_config_document(name, source)
}

///|
pub fn parse_moon_mod(
  name? : String = "moon.mod",
  source : String,
) -> (Ast, Array[@basic.Report]) {
  parse_moon_mod_document(name, source)
}
