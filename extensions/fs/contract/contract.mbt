///|
pub(all) struct PathRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ReadFileRequest {
  path : String
  sync_timestamp : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ReadFileReply {
  path : String
  content : String
  bytes_read : Int
} derive(ToJson, FromJson, Debug, Eq)

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
pub(all) struct WriteFileReply {
  path : String
  bytes_written : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ExistsReply {
  exists : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KindRequest {
  path : String
  follow_symlink : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KindReply {
  path : String
  kind : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SizeReply {
  path : String
  size : Int64
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ReaddirRequest {
  path : String
  include_hidden : Bool?
  include_special : Bool?
  sort : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ReaddirReply {
  path : String
  entries : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MkdirRequest {
  path : String
  permission : Int?
  recursive : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MkdirReply {
  path : String
  created : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RemoveFileReply {
  removed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RemovePathRequest {
  path : String
  recursive : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RemovePathReply {
  path : String
  removed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RenameRequest {
  old_path : String
  new_path : String
  replace : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RenameReply {
  old_path : String
  new_path : String
  renamed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RealpathReply {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct FsActivity {
  operation : String
  path : String?
  bytes : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-fs",
  js_namespace="fs",
)

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
