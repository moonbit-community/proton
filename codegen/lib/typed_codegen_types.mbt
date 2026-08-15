///|
/// Generated MoonBit registrar source and diagnostics.
pub(all) struct ProtonCommandCodegenOutput {
  source : String
  warnings : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub extend ProtonCommandCodegenOutput with Eq::{not_equal, equal}

///|
pub extend ProtonCommandCodegenOutput with Debug::{to_repr}

///|
pub extend ProtonCommandCodegenOutput with ToJson::{to_json}

///|
priv struct ParsedTypedCommand {
  function_name : String
  receiver_type : String?
  contract_expression : String
  accepts_context : Bool
  has_request : Bool
}

///|
priv struct ParsedTypedModule {
  commands : Array[ParsedTypedCommand]
  extension_package : Bool
}
