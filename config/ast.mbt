///|
pub type ConfigLoc = @basic.Location

///|
pub(all) struct ConfigField {
  key : String
  key_loc : ConfigLoc
  value : Ast
} derive(Eq, Debug)

///|
pub(all) enum Ast {
  Bool(Bool, ConfigLoc)
  Str(String, ConfigLoc)
  Int(String, ConfigLoc)
  Arr(Array[Ast], ConfigLoc)
  Obj(Array[ConfigField], ConfigLoc)
} derive(Eq, Debug)

///|
pub fn Ast::loc(self : Ast) -> ConfigLoc {
  match self {
    Bool(_, loc) => loc
    Str(_, loc) => loc
    Int(_, loc) => loc
    Arr(_, loc) => loc
    Obj(_, loc) => loc
  }
}
