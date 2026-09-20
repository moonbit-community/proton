///|
priv struct MacosHelperSpec {
  bundle_name : String
  executable_name : String
  bundle_identifier : String
}

///|
priv enum StagingHost {
  Macos
  Windows
  Linux
} derive(Eq)
