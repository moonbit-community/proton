///|
/// Installs a remote-op bridge script on one webview.
///
/// `core` only knows how to expose the JavaScript runtime surface. The concrete
/// IPC transport is supplied as script text by another module, for example
/// `lepus_ipc_ws`.
pub fn install_ipc_bridge_runtime(
  webview : @webview.Webview,
  bridge_script : String,
  op_names : Array[String],
  extensions? : Array[@ipc.IpcExtensionDescriptor] = [],
) -> Unit {
  match
    validate_ipc_bridge_runtime_config(bridge_script, op_names, extensions) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  // 先建立扩展 namespace，再让 IPC bridge 接管 core.invokeOp；否则后续安装
  // extension metadata 会把远程 bridge 覆盖成本地 op runtime。
  install_moonbit_core_runtime(webview)
  for descriptor in extensions {
    install_ipc_extension(webview, descriptor)
  }
  install_runtime_script(webview, bridge_script)
  for op_name in op_names {
    register_moonbit_op(webview, op_name)
  }
}

///|
/// Installs JavaScript metadata for one remote extension.
///
/// The actual command handlers live in the user process; this function only
/// exposes `window.__MoonBit__.<namespace>.*` helper methods in the webview.
pub fn install_ipc_extension(
  webview : @webview.Webview,
  descriptor : @ipc.IpcExtensionDescriptor,
) -> Unit {
  match validate_ipc_extension_install_descriptor(descriptor) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  install_moonbit_core_runtime(webview)
  install_extension_namespace(webview, descriptor.js_namespace)
  for api in descriptor.apis {
    register_moonbit_op(
      webview,
      extension_op_name(descriptor.js_namespace, api.api_name),
    )
  }
  install_extension_scripts(webview, descriptor.scripts)
}

///|
fn validate_ipc_bridge_runtime_config(
  bridge_script : String,
  op_names : Array[String],
  extensions : Array[@ipc.IpcExtensionDescriptor],
) -> Result[Unit, String] {
  guard bridge_script.trim().to_owned() != "" else {
    return Err("install_ipc_bridge_runtime: bridge script must not be empty")
  }
  let ops : Map[String, Bool] = {}
  for op_name in op_names {
    guard op_name.trim().to_owned() != "" else {
      return Err("install_ipc_bridge_runtime: op name must not be empty")
    }
    guard ops.get(op_name) is None else {
      return Err("install_ipc_bridge_runtime: duplicate op name: " + op_name)
    }
    ops[op_name] = true
  }
  let ids : Map[String, Bool] = {}
  let namespaces : Map[String, Bool] = {}
  for descriptor in extensions {
    match validate_ipc_extension_descriptor(descriptor, ops, ids, namespaces) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn validate_ipc_extension_install_descriptor(
  descriptor : @ipc.IpcExtensionDescriptor,
) -> Result[Unit, String] {
  guard descriptor.id.trim().to_owned() != "" else {
    return Err("install_ipc_extension: extension id must not be empty")
  }
  guard descriptor.js_namespace.trim().to_owned() != "" else {
    return Err("install_ipc_extension: extension namespace must not be empty")
  }
  guard !extension_namespace_is_reserved(descriptor.js_namespace) else {
    return Err(
      "install_ipc_extension: reserved extension namespace: " +
      descriptor.js_namespace,
    )
  }
  guard descriptor.apis.length() > 0 else {
    return Err(
      "install_ipc_extension: extension must expose at least one API: " +
      descriptor.id,
    )
  }
  let api_names : Map[String, Bool] = {}
  for api in descriptor.apis {
    guard api.api_name.trim().to_owned() != "" else {
      return Err(
        "install_ipc_extension: extension API name must not be empty: " +
        descriptor.id,
      )
    }
    guard !extension_is_reserved_api_name(api.api_name) else {
      return Err("install_ipc_extension: reserved API name: " + api.api_name)
    }
    guard api_names.get(api.api_name) is None else {
      return Err(
        "install_ipc_extension: duplicate extension API: " +
        descriptor.id +
        "." +
        api.api_name,
      )
    }
    api_names[api.api_name] = true
  }
  Ok(())
}

///|
fn validate_ipc_extension_descriptor(
  descriptor : @ipc.IpcExtensionDescriptor,
  op_names : Map[String, Bool],
  ids : Map[String, Bool],
  namespaces : Map[String, Bool],
) -> Result[Unit, String] {
  guard descriptor.id.trim().to_owned() != "" else {
    return Err("install_ipc_bridge_runtime: extension id must not be empty")
  }
  guard ids.get(descriptor.id) is None else {
    return Err(
      "install_ipc_bridge_runtime: duplicate extension id: " + descriptor.id,
    )
  }
  ids[descriptor.id] = true
  guard descriptor.js_namespace.trim().to_owned() != "" else {
    return Err(
      "install_ipc_bridge_runtime: extension namespace must not be empty: " +
      descriptor.id,
    )
  }
  guard !extension_namespace_is_reserved(descriptor.js_namespace) else {
    return Err(
      "install_ipc_bridge_runtime: reserved extension namespace: " +
      descriptor.js_namespace,
    )
  }
  guard namespaces.get(descriptor.js_namespace) is None else {
    return Err(
      "install_ipc_bridge_runtime: duplicate extension namespace: " +
      descriptor.js_namespace,
    )
  }
  namespaces[descriptor.js_namespace] = true
  validate_ipc_extension_descriptor_apis(descriptor, op_names)
}

///|
fn validate_ipc_extension_descriptor_apis(
  descriptor : @ipc.IpcExtensionDescriptor,
  op_names : Map[String, Bool],
) -> Result[Unit, String] {
  guard descriptor.apis.length() > 0 else {
    return Err(
      "install_ipc_bridge_runtime: extension must expose at least one API: " +
      descriptor.id,
    )
  }
  let api_names : Map[String, Bool] = {}
  for api in descriptor.apis {
    guard api.api_name.trim().to_owned() != "" else {
      return Err(
        "install_ipc_bridge_runtime: extension API name must not be empty: " +
        descriptor.id,
      )
    }
    guard !extension_is_reserved_api_name(api.api_name) else {
      return Err(
        "install_ipc_bridge_runtime: reserved API name: " + api.api_name,
      )
    }
    guard api_names.get(api.api_name) is None else {
      return Err(
        "install_ipc_bridge_runtime: duplicate extension API: " +
        descriptor.id +
        "." +
        api.api_name,
      )
    }
    api_names[api.api_name] = true
    let op_name = extension_op_name(descriptor.js_namespace, api.api_name)
    guard op_names.get(op_name) is Some(_) else {
      return Err(
        "install_ipc_bridge_runtime: extension API is missing op: " + op_name,
      )
    }
  }
  Ok(())
}

///|
/// Emits one remote extension event into JavaScript.
pub fn emit_ipc_extension_event(
  webview : @webview.Webview,
  event : @ipc.IpcExtensionEvent,
) -> Unit {
  let script = make_extension_emit_script(
    event.extension_namespace,
    event.event_name,
    event.payload.stringify(),
  )
  webview.dispatch(fn() { webview.eval(script) })
}
