///|
/// Registers the path-oriented filesystem APIs.
fn register_path_ops(extension : @core.ExtensionContext) -> Unit {
  register_stat_op(extension)
  register_readdir_op(extension)
  register_mkdir_op(extension)
  register_unlink_op(extension)
  register_remove_path_op(extension, "rm")
  register_remove_path_op(extension, "remove")
  register_rename_op(extension)
  register_copy_file_op(extension)
  register_realpath_op(extension)
  register_truncate_op(extension)
  register_size_op(extension)
  register_exists_op(extension)
  register_remove_file_op(extension)
  register_read_dir_op(extension)
  register_resolve_path_op(extension)
}

///|
fn register_stat_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("stat", fn(payload : StatPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      stat_path(resolved_path, option_bool(payload.throw_if_no_entry, true)).map(fn(
          reply,
        ) {
          emit_activity(
            extension,
            "stat",
            path=Some(resolved_path),
            bytes=Some(reply.size),
          )
          reply
        },
      )
    })
  })
}

///|
fn register_readdir_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("readdir", fn(payload : ReaddirPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      readdir_entries(resolved_path, option_bool(payload.recursive, false)).map(fn(
          entries,
        ) {
          emit_activity(extension, "readdir", path=Some(resolved_path))
          ReaddirReply::{ path: resolved_path, entries }
        },
      )
    })
  })
}

///|
fn register_mkdir_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("mkdir", fn(payload : MkdirPayload) {
    with_resolved_path(payload.path, resolve_write_path, fn(resolved_path) {
      mkdir_path(resolved_path, option_bool(payload.recursive, false)).map(fn(
        created,
      ) {
        emit_activity(extension, "mkdir", path=Some(resolved_path))
        MkdirReply::{ path: resolved_path, created }
      })
    })
  })
}

///|
fn register_unlink_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("unlink", fn(payload : RemoveFilePayload) {
    with_resolved_path(payload.path, resolve_remove_path, fn(resolved_path) {
      if !native_path_exists(resolved_path) {
        Err("Failed to unlink path: path does not exist")
      } else {
        native_remove_file(resolved_path).map(fn(removed) {
          emit_activity(extension, "unlink", path=Some(resolved_path))
          RemoveFileReply::{ removed, }
        })
      }
    })
  })
}

///|
fn register_rename_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("rename", fn(payload : RenamePayload) {
    with_resolved_paths(
      payload.old_path,
      resolve_remove_path,
      payload.new_path,
      resolve_write_path,
      fn(old_path, new_path) {
        rename_path(old_path, new_path).map(fn(_) {
          emit_activity(extension, "rename", path=Some(new_path))
          RenameReply::{ old_path, new_path, renamed: true }
        })
      },
    )
  })
}

///|
fn register_copy_file_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("copyFile", fn(payload : CopyFilePayload) {
    with_resolved_paths(
      payload.src,
      resolve_read_path,
      payload.dest,
      resolve_write_path,
      fn(src, dest) {
        copy_file_path(src, dest, option_bool(payload.overwrite, true)).map(fn(
          bytes_copied,
        ) {
          emit_activity(
            extension,
            "copyFile",
            path=Some(dest),
            bytes=Some(bytes_copied),
          )
          CopyFileReply::{ src, dest, copied: true, bytes_copied }
        })
      },
    )
  })
}

///|
fn register_realpath_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("realpath", fn(payload : ResolvePathPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      realpath_path(resolved_path).map(fn(real_path) {
        emit_activity(extension, "realpath", path=Some(real_path))
        ResolvePathReply::{ path: real_path }
      })
    })
  })
}

///|
fn register_truncate_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("truncate", fn(payload : TruncatePayload) {
    with_resolved_path(payload.path, resolve_write_path, fn(resolved_path) {
      let len = match payload.len {
        Some(len) => len
        None => 0
      }
      truncate_path(resolved_path, len).map(fn(size) {
        emit_activity(
          extension,
          "truncate",
          path=Some(resolved_path),
          bytes=Some(size),
        )
        TruncateReply::{ path: resolved_path, size, truncated: true }
      })
    })
  })
}

///|
fn register_size_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("size", fn(payload : SizePayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      recursive_path_size(resolved_path).map(fn(size) {
        emit_activity(
          extension,
          "size",
          path=Some(resolved_path),
          bytes=Some(size),
        )
        SizeReply::{ path: resolved_path, size }
      })
    })
  })
}

///|
fn register_exists_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("exists", fn(payload : ExistsPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      Ok(ExistsReply::{ exists: native_path_exists(resolved_path) })
    })
  })
}

///|
fn register_remove_file_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("removeFile", fn(payload : RemoveFilePayload) {
    with_resolved_path(payload.path, resolve_remove_path, fn(resolved_path) {
      native_remove_file(resolved_path).map(fn(removed) {
        emit_activity(extension, "removeFile", path=Some(resolved_path))
        RemoveFileReply::{ removed, }
      })
    })
  })
}

///|
fn register_read_dir_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("readDir", fn(payload : ReadDirPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      native_read_dir(resolved_path).map(fn(entries) {
        emit_activity(extension, "readDir", path=Some(resolved_path))
        ReadDirReply::{ entries, }
      })
    })
  })
}

///|
fn register_resolve_path_op(extension : @core.ExtensionContext) -> Unit {
  extension.op_result("resolvePath", fn(payload : ResolvePathPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      Ok(ResolvePathReply::{ path: resolved_path })
    })
  })
}

///|
/// Registers one remove-path style API with shared recursive and force semantics.
fn register_remove_path_op(
  extension : @core.ExtensionContext,
  api_name : String,
) -> Unit {
  extension.op_result(api_name, fn(payload : RemovePathPayload) {
    with_resolved_path(payload.path, resolve_remove_path, fn(resolved_path) {
      remove_path(
        resolved_path,
        option_bool(payload.recursive, false),
        option_bool(payload.force, false),
      ).map(fn(removed) {
        emit_activity(extension, api_name, path=Some(resolved_path))
        RemovePathReply::{ path: resolved_path, removed }
      })
    })
  })
}
