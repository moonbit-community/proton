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
  extension_identity : (String, String)?
}
