///|
/// Generated MoonBit source and diagnostics returned by Proton attribute codegen.
///
/// `source` is the complete `.g.mbt` file content. `warnings` contains
/// non-fatal messages that the CLI should show after writing the file.
pub(all) struct ProtonCommandCodegenOutput {
  source : String
  warnings : Array[String]
} derive(Eq, Debug, ToJson)

///|
priv struct ParsedProtonCommand {
  function_name : String
  js_name : String
  params : Array[ParsedProtonParam]
  return_type : String
  is_async : Bool
  has_context : Bool
  has_request_context : Bool
  error_effect : String?
}

///|
priv struct ParsedProtonParam {
  name : String
  param_type : String
  is_context : Bool
  is_request_context : Bool
}

///|
priv struct ParsedProtonEvent {
  type_name : String
  js_name : String
  helper_name : String
}

///|
priv struct ParsedProtonScript {
  function_name : String
}

///|
priv struct ParsedProtonDestroy {
  function_name : String
  has_context : Bool
  error_effect : String?
}

///|
priv enum ProtonAttributeKind {
  Command
  Event
  Script
  Destroy
}

///|
priv struct ProtonAttribute {
  kind : ProtonAttributeKind
  name_override : String?
}

///|
priv struct ParsedProtonModule {
  commands : Array[ParsedProtonCommand]
  events : Array[ParsedProtonEvent]
  scripts : Array[ParsedProtonScript]
  mut destroy : ParsedProtonDestroy?
  package_commands : Array[ParsedProtonCommand]
  package_events : Array[ParsedProtonEvent]
}
