///|
pub(all) struct PathRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PathRequest with Eq::{not_equal, equal}

///|
pub extend PathRequest with Debug::{to_repr}

///|
pub extend PathRequest with ToJson::{to_json}

///|
pub extend PathRequest with FromJson::{from_json}

///|
pub(all) struct ReadFileRequest {
  path : String
  sync_timestamp : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ReadFileRequest with Eq::{not_equal, equal}

///|
pub extend ReadFileRequest with Debug::{to_repr}

///|
pub extend ReadFileRequest with ToJson::{to_json}

///|
pub extend ReadFileRequest with FromJson::{from_json}

///|
pub(all) struct ReadFileReply {
  path : String
  content : String
  bytes_read : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ReadFileReply with Eq::{not_equal, equal}

///|
pub extend ReadFileReply with Debug::{to_repr}

///|
pub extend ReadFileReply with ToJson::{to_json}

///|
pub extend ReadFileReply with FromJson::{from_json}

///|
pub(all) struct WriteFileRequest {
  path : String
  content : String
  append : Bool?
  create_mode : String?
  permission : Int?
  sync : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend WriteFileRequest with Eq::{not_equal, equal}

///|
pub extend WriteFileRequest with Debug::{to_repr}

///|
pub extend WriteFileRequest with ToJson::{to_json}

///|
pub extend WriteFileRequest with FromJson::{from_json}

///|
pub(all) struct WriteFileReply {
  path : String
  bytes_written : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend WriteFileReply with Eq::{not_equal, equal}

///|
pub extend WriteFileReply with Debug::{to_repr}

///|
pub extend WriteFileReply with ToJson::{to_json}

///|
pub extend WriteFileReply with FromJson::{from_json}

///|
pub(all) struct ExistsReply {
  exists : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ExistsReply with Eq::{not_equal, equal}

///|
pub extend ExistsReply with Debug::{to_repr}

///|
pub extend ExistsReply with ToJson::{to_json}

///|
pub extend ExistsReply with FromJson::{from_json}

///|
pub(all) struct KindRequest {
  path : String
  follow_symlink : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KindRequest with Eq::{not_equal, equal}

///|
pub extend KindRequest with Debug::{to_repr}

///|
pub extend KindRequest with ToJson::{to_json}

///|
pub extend KindRequest with FromJson::{from_json}

///|
pub(all) struct KindReply {
  path : String
  kind : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KindReply with Eq::{not_equal, equal}

///|
pub extend KindReply with Debug::{to_repr}

///|
pub extend KindReply with ToJson::{to_json}

///|
pub extend KindReply with FromJson::{from_json}

///|
pub(all) struct SizeReply {
  path : String
  size : Int64
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SizeReply with Eq::{not_equal, equal}

///|
pub extend SizeReply with Debug::{to_repr}

///|
pub extend SizeReply with ToJson::{to_json}

///|
pub extend SizeReply with FromJson::{from_json}

///|
pub(all) struct ReaddirRequest {
  path : String
  include_hidden : Bool?
  include_special : Bool?
  sort : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ReaddirRequest with Eq::{not_equal, equal}

///|
pub extend ReaddirRequest with Debug::{to_repr}

///|
pub extend ReaddirRequest with ToJson::{to_json}

///|
pub extend ReaddirRequest with FromJson::{from_json}

///|
pub(all) struct ReaddirReply {
  path : String
  entries : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ReaddirReply with Eq::{not_equal, equal}

///|
pub extend ReaddirReply with Debug::{to_repr}

///|
pub extend ReaddirReply with ToJson::{to_json}

///|
pub extend ReaddirReply with FromJson::{from_json}

///|
pub(all) struct MkdirRequest {
  path : String
  permission : Int?
  recursive : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MkdirRequest with Eq::{not_equal, equal}

///|
pub extend MkdirRequest with Debug::{to_repr}

///|
pub extend MkdirRequest with ToJson::{to_json}

///|
pub extend MkdirRequest with FromJson::{from_json}

///|
pub(all) struct MkdirReply {
  path : String
  created : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MkdirReply with Eq::{not_equal, equal}

///|
pub extend MkdirReply with Debug::{to_repr}

///|
pub extend MkdirReply with ToJson::{to_json}

///|
pub extend MkdirReply with FromJson::{from_json}

///|
pub(all) struct RemoveFileReply {
  removed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RemoveFileReply with Eq::{not_equal, equal}

///|
pub extend RemoveFileReply with Debug::{to_repr}

///|
pub extend RemoveFileReply with ToJson::{to_json}

///|
pub extend RemoveFileReply with FromJson::{from_json}

///|
pub(all) struct RemovePathRequest {
  path : String
  recursive : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RemovePathRequest with Eq::{not_equal, equal}

///|
pub extend RemovePathRequest with Debug::{to_repr}

///|
pub extend RemovePathRequest with ToJson::{to_json}

///|
pub extend RemovePathRequest with FromJson::{from_json}

///|
pub(all) struct RemovePathReply {
  path : String
  removed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RemovePathReply with Eq::{not_equal, equal}

///|
pub extend RemovePathReply with Debug::{to_repr}

///|
pub extend RemovePathReply with ToJson::{to_json}

///|
pub extend RemovePathReply with FromJson::{from_json}

///|
pub(all) struct RenameRequest {
  old_path : String
  new_path : String
  replace : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RenameRequest with Eq::{not_equal, equal}

///|
pub extend RenameRequest with Debug::{to_repr}

///|
pub extend RenameRequest with ToJson::{to_json}

///|
pub extend RenameRequest with FromJson::{from_json}

///|
pub(all) struct RenameReply {
  old_path : String
  new_path : String
  renamed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RenameReply with Eq::{not_equal, equal}

///|
pub extend RenameReply with Debug::{to_repr}

///|
pub extend RenameReply with ToJson::{to_json}

///|
pub extend RenameReply with FromJson::{from_json}

///|
pub(all) struct RealpathReply {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RealpathReply with Eq::{not_equal, equal}

///|
pub extend RealpathReply with Debug::{to_repr}

///|
pub extend RealpathReply with ToJson::{to_json}

///|
pub extend RealpathReply with FromJson::{from_json}

///|
pub(all) struct FsActivity {
  operation : String
  path : String?
  bytes : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend FsActivity with Eq::{not_equal, equal}

///|
pub extend FsActivity with Debug::{to_repr}

///|
pub extend FsActivity with ToJson::{to_json}

///|
pub extend FsActivity with FromJson::{from_json}

///|
pub let read_file : @proton_contract.Command[ReadFileRequest, ReadFileReply] = extension.command(
  "read_file",
)

///|
pub let write_file : @proton_contract.Command[WriteFileRequest, WriteFileReply] = extension.command(
  "write_file",
)

///|
pub let exists : @proton_contract.Command[PathRequest, ExistsReply] = extension.command(
  "exists",
)

///|
pub let kind : @proton_contract.Command[KindRequest, KindReply] = extension.command(
  "kind",
)

///|
pub let size : @proton_contract.Command[PathRequest, SizeReply] = extension.command(
  "size",
)

///|
pub let readdir : @proton_contract.Command[ReaddirRequest, ReaddirReply] = extension.command(
  "readdir",
)

///|
pub let mkdir : @proton_contract.Command[MkdirRequest, MkdirReply] = extension.command(
  "mkdir",
)

///|
pub let remove : @proton_contract.Command[PathRequest, RemoveFileReply] = extension.command(
  "remove",
)

///|
pub let rmdir : @proton_contract.Command[RemovePathRequest, RemovePathReply] = extension.command(
  "rmdir",
)

///|
pub let rename : @proton_contract.Command[RenameRequest, RenameReply] = extension.command(
  "rename",
)

///|
pub let realpath : @proton_contract.Command[PathRequest, RealpathReply] = extension.command(
  "realpath",
)

///|
pub let activity : @proton_contract.Event[FsActivity] = extension.event(
  "activity",
)
