///|
#proton.event(name="activity")
struct FsActivity {
  operation : String
  path : String?
  bytes : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
async fn emit_activity(
  context : @proton_command.AppCommandExtensionContext,
  operation : String,
  path? : String? = None,
  bytes? : Int? = None,
) -> Unit {
  emit_fs_activity(context, FsActivity::{ operation, path, bytes })
}

///|
#proton.command(name="read_file")
async fn read_file(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  sync_timestamp : Bool?,
) -> Result[ReadFileReply, String] {
  match read_text_file({ path, sync_timestamp }) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_activity(
        context,
        "read_file",
        path=Some(reply.path),
        bytes=Some(reply.bytes_read),
      )
      Ok(reply)
    }
  }
}

///|
#proton.command(name="write_file")
async fn write_file(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  content : String,
  append : Bool?,
  create_mode : String?,
  permission : Int?,
  sync : String?,
) -> Result[WriteFileReply, String] {
  match
    write_text_file({ path, content, append, create_mode, permission, sync }) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_activity(
        context,
        "write_file",
        path=Some(reply.path),
        bytes=Some(reply.bytes_written),
      )
      Ok(reply)
    }
  }
}

///|
#proton.command(name="exists")
async fn exists(path : String) -> Result[ExistsReply, String] {
  exists_path(path).map(fn(exists) { ExistsReply::{ exists, } })
}

///|
#proton.command(name="kind")
async fn kind(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  follow_symlink : Bool?,
) -> Result[KindReply, String] {
  match path_kind(path, option_bool(follow_symlink, true)) {
    Err(error) => Err(error)
    Ok(kind) => {
      emit_activity(context, "kind", path=Some(path))
      Ok(KindReply::{ path, kind })
    }
  }
}

///|
#proton.command(name="size")
async fn size(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> Result[SizeReply, String] {
  match path_size(path) {
    Err(error) => Err(error)
    Ok(size) => {
      emit_activity(context, "size", path=Some(path))
      Ok(SizeReply::{ path, size })
    }
  }
}

///|
#proton.command(name="readdir")
async fn readdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  include_hidden : Bool?,
  include_special : Bool?,
  sort : Bool?,
) -> Result[ReaddirReply, String] {
  match readdir_entries({ path, include_hidden, include_special, sort }) {
    Err(error) => Err(error)
    Ok(entries) => {
      emit_activity(context, "readdir", path=Some(path))
      Ok(ReaddirReply::{ path, entries })
    }
  }
}

///|
#proton.command(name="mkdir")
async fn mkdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  permission : Int?,
  recursive : Bool?,
) -> Result[MkdirReply, String] {
  match mkdir_path({ path, permission, recursive }) {
    Err(error) => Err(error)
    Ok(created) => {
      emit_activity(context, "mkdir", path=Some(path))
      Ok(MkdirReply::{ path, created })
    }
  }
}

///|
#proton.command(name="remove")
async fn remove(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> Result[RemoveFileReply, String] {
  match remove_file(path) {
    Err(error) => Err(error)
    Ok(removed) => {
      emit_activity(context, "remove", path=Some(path))
      Ok(RemoveFileReply::{ removed, })
    }
  }
}

///|
#proton.command(name="rmdir")
async fn rmdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  recursive : Bool?,
) -> Result[RemovePathReply, String] {
  match remove_dir({ path, recursive }) {
    Err(error) => Err(error)
    Ok(removed) => {
      emit_activity(context, "rmdir", path=Some(path))
      Ok(RemovePathReply::{ path, removed })
    }
  }
}

///|
#proton.command(name="rename")
async fn rename(
  context : @proton_command.AppCommandExtensionContext,
  old_path : String,
  new_path : String,
  replace : Bool?,
) -> Result[RenameReply, String] {
  match rename_path({ old_path, new_path, replace }) {
    Err(error) => Err(error)
    Ok(_) => {
      emit_activity(context, "rename", path=Some(new_path))
      Ok(RenameReply::{ old_path, new_path, renamed: true })
    }
  }
}

///|
#proton.command(name="realpath")
async fn realpath(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> Result[RealpathReply, String] {
  match realpath_path(path) {
    Err(error) => Err(error)
    Ok(real_path) => {
      emit_activity(context, "realpath", path=Some(real_path))
      Ok(RealpathReply::{ path: real_path })
    }
  }
}
