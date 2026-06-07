///|
/// Generated MoonBit source and diagnostics returned by Lepus attribute codegen.
///
/// `source` is the complete `.g.mbt` file content. `warnings` contains
/// non-fatal messages that the CLI should show after writing the file.
pub(all) struct LepusCommandCodegenOutput {
  source : String
  warnings : Array[String]
} derive(Eq, Debug, ToJson)

///|
priv struct ParsedLepusCommand {
  function_name : String
  js_name : String
  params : Array[ParsedLepusParam]
  return_type : String
  is_async : Bool
  has_context : Bool
  returns_result : Bool
}

///|
priv struct ParsedLepusParam {
  name : String
  param_type : String
  is_context : Bool
}

///|
priv struct ParsedLepusEvent {
  type_name : String
  js_name : String
  helper_name : String
}

///|
priv enum LepusAttributeKind {
  Command
  Event
} derive(Eq)

///|
priv struct LepusAttribute {
  kind : LepusAttributeKind
  name_override : String?
}

///|
priv struct ParsedLepusModule {
  commands : Array[ParsedLepusCommand]
  events : Array[ParsedLepusEvent]
  package_commands : Array[ParsedLepusCommand]
  package_events : Array[ParsedLepusEvent]
}
