///|
test "AppIpcBackend copies command extension descriptors" {
  let descriptor = @ipc.IpcExtensionDescriptor::new(
    "vendor/demo",
    "demo",
    [@ipc.IpcExtensionApi::new("ping")],
    scripts=["window.__demo = true;"],
  )
  let backend = AppIpcBackend::new("bridge", ["ext:demo/ping"], [descriptor])
  descriptor.apis.push(@ipc.IpcExtensionApi::new("changed"))
  descriptor.scripts.push("window.__demo = false;")

  let snapshot = backend.extensions()
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0].apis.length(), 1)
  assert_eq(snapshot[0].scripts.length(), 1)

  snapshot[0].apis.push(@ipc.IpcExtensionApi::new("later"))
  snapshot[0].scripts.push("window.__demo = null;")
  let fresh = backend.extensions()
  assert_eq(fresh[0].apis.length(), 1)
  assert_eq(fresh[0].scripts.length(), 1)
}

///|
test "App IPC backend rejects empty bridge script" {
  let backend = AppIpcBackend::new("  ", [], [])
  match validate_app_ipc_backend_config({}, backend) {
    Err(error) =>
      assert_eq(
        error, "App::install_ipc_bridge: bridge script must not be empty",
      )
    Ok(_) => abort("expected empty IPC bridge script error")
  }
}

///|
test "App IPC backend rejects local extension namespace collision" {
  let local_namespaces : Map[String, Bool] = { "demo": true }
  let backend = AppIpcBackend::new("bridge", ["ext:demo/ping"], [
    @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
      @ipc.IpcExtensionApi::new("ping"),
    ]),
  ])
  match validate_app_ipc_backend_config(local_namespaces, backend) {
    Err(error) =>
      assert_eq(
        error, "App::install_ipc_bridge: extension namespace already installed: demo",
      )
    Ok(_) => abort("expected IPC namespace collision error")
  }
}

///|
test "App detects installed IPC extension namespace" {
  let backends = [
    AppIpcBackend::new("bridge", ["ext:demo/ping"], [
      @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
        @ipc.IpcExtensionApi::new("ping"),
      ]),
    ]),
  ]
  assert_true(ipc_extension_namespace_is_installed(backends, "demo"))
  assert_false(ipc_extension_namespace_is_installed(backends, "other"))
}
