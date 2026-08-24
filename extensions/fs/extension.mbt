///|
let read_file_command = @fs_contract.read_file

///|
let write_file_command = @fs_contract.write_file

///|
let exists_command = @fs_contract.exists

///|
let kind_command = @fs_contract.kind

///|
let size_command = @fs_contract.size

///|
let readdir_command = @fs_contract.readdir

///|
let mkdir_command = @fs_contract.mkdir

///|
let remove_command = @fs_contract.remove

///|
let rmdir_command = @fs_contract.rmdir

///|
let rename_command = @fs_contract.rename

///|
let realpath_command = @fs_contract.realpath

///|
async fn emit_activity(
  context : @proton.CommandContext,
  operation : String,
  path? : String? = None,
  bytes? : Int? = None,
) -> Unit {
  context.emit(@fs_contract.activity, @fs_contract.FsActivity::{
    operation,
    path,
    bytes,
  })
}

///|
#proton.command(contract=read_file_command)
async fn read_file(
  context : @proton.CommandContext,
  request : @fs_contract.ReadFileRequest,
) -> @fs_contract.ReadFileReply {
  let reply = with_authorized_path(context, "read_file", request.path, resolved => {
    read_text_file({ path: resolved, sync_timestamp: request.sync_timestamp, })
  })
  emit_activity(
    context,
    "read_file",
    path=Some(request.path),
    bytes=Some(reply.bytes_read),
  )
  @fs_contract.ReadFileReply::{
    path: request.path,
    content: reply.content,
    bytes_read: reply.bytes_read,
  }
}

///|
#proton.command(contract=write_file_command)
async fn write_file(
  context : @proton.CommandContext,
  request : @fs_contract.WriteFileRequest,
) -> @fs_contract.WriteFileReply {
  let reply = with_authorized_path(context, "write_file", request.path, resolved => {
    write_text_file({
      path: resolved,
      content: request.content,
      append: request.append,
      create_mode: request.create_mode,
      permission: request.permission,
      sync: request.sync,
    })
  })
  emit_activity(
    context,
    "write_file",
    path=Some(request.path),
    bytes=Some(reply.bytes_written),
  )
  @fs_contract.WriteFileReply::{
    path: request.path,
    bytes_written: reply.bytes_written,
  }
}

///|
#proton.command(contract=exists_command)
async fn exists(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.ExistsReply {
  let exists = with_authorized_path(context, "exists", request.path, resolved => {
    exists_path(resolved)
  })
  @fs_contract.ExistsReply::{ exists, }
}

///|
#proton.command(contract=kind_command)
async fn kind(
  context : @proton.CommandContext,
  request : @fs_contract.KindRequest,
) -> @fs_contract.KindReply {
  let kind = with_authorized_path(context, "kind", request.path, resolved => {
    path_kind(resolved, option_bool(request.follow_symlink, true))
  })
  emit_activity(context, "kind", path=Some(request.path))
  @fs_contract.KindReply::{ path: request.path, kind, }
}

///|
#proton.command(contract=size_command)
async fn size(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.SizeReply {
  let size = with_authorized_path(context, "size", request.path, resolved => {
    path_size(resolved)
  })
  emit_activity(context, "size", path=Some(request.path))
  @fs_contract.SizeReply::{ path: request.path, size, }
}

///|
#proton.command(contract=readdir_command)
async fn readdir(
  context : @proton.CommandContext,
  request : @fs_contract.ReaddirRequest,
) -> @fs_contract.ReaddirReply {
  let entries = with_authorized_path(context, "readdir", request.path, resolved => {
    readdir_entries({
      path: resolved,
      include_hidden: request.include_hidden,
      include_special: request.include_special,
      sort: request.sort,
    })
  })
  emit_activity(context, "readdir", path=Some(request.path))
  @fs_contract.ReaddirReply::{ path: request.path, entries, }
}

///|
#proton.command(contract=mkdir_command)
async fn mkdir(
  context : @proton.CommandContext,
  request : @fs_contract.MkdirRequest,
) -> @fs_contract.MkdirReply {
  let created = with_authorized_path(context, "mkdir", request.path, resolved => {
    mkdir_path({
      path: resolved,
      permission: request.permission,
      recursive: request.recursive,
    })
  })
  emit_activity(context, "mkdir", path=Some(request.path))
  @fs_contract.MkdirReply::{ path: request.path, created, }
}

///|
#proton.command(contract=remove_command)
async fn remove(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.RemoveFileReply {
  let removed = with_authorized_path(context, "remove", request.path, resolved => {
    remove_file(resolved)
  })
  emit_activity(context, "remove", path=Some(request.path))
  @fs_contract.RemoveFileReply::{ removed, }
}

///|
#proton.command(contract=rmdir_command)
async fn rmdir(
  context : @proton.CommandContext,
  request : @fs_contract.RemovePathRequest,
) -> @fs_contract.RemovePathReply {
  let removed = with_authorized_path(context, "rmdir", request.path, resolved => {
    remove_dir({ path: resolved, recursive: request.recursive, })
  })
  emit_activity(context, "rmdir", path=Some(request.path))
  @fs_contract.RemovePathReply::{ path: request.path, removed, }
}

///|
#proton.command(contract=rename_command)
async fn rename(
  context : @proton.CommandContext,
  request : @fs_contract.RenameRequest,
) -> @fs_contract.RenameReply {
  with_authorized_paths(context, "rename", request.old_path, request.new_path, (
    old_path,
    new_path,
  ) => rename_path({ old_path, new_path, replace: request.replace, }))
  emit_activity(context, "rename", path=Some(request.new_path))
  @fs_contract.RenameReply::{
    old_path: request.old_path,
    new_path: request.new_path,
    renamed: true,
  }
}

///|
#proton.command(contract=realpath_command)
async fn realpath(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.RealpathReply {
  let real_path = with_authorized_path(context, "realpath", request.path, resolved => {
    realpath_path(resolved)
  })
  emit_activity(context, "realpath", path=Some(real_path))
  @fs_contract.RealpathReply::{ path: real_path, }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @fs_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    resolve_permission=resolve_fs_permission_scope,
  )
}
