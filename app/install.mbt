///|
/// Builds a runtime app from previously prepared internal app state.
fn build_prepared_app(
  prepared : PreparedApp,
  app_service? : AppServiceConfig? = None,
  mbt_backend? : MbtProcessBackendConfig? = None,
) -> Result[@wvrt.App, String] {
  let app = @wvrt.App::new(prepared.runtime_config())
  match
    install_prepared_extensions(
      app,
      prepared.prepared_extensions(),
      prepared.base_dir(),
    ) {
    Err(error) => {
      app.destroy()
      Err(error)
    }
    Ok(_) =>
      match
        install_prepared_app_service(app, app_service, prepared.base_dir()) {
        Err(error) => {
          app.destroy()
          Err(error)
        }
        Ok(_) =>
          match
            install_prepared_mbt_backend(app, mbt_backend, prepared.base_dir()) {
            Ok(_) => Ok(app)
            Err(error) => {
              app.destroy()
              Err(error)
            }
          }
      }
  }
}

///|
/// Installs one optional prepared app service into the runtime app.
fn install_prepared_app_service(
  app : @wvrt.App,
  service : AppServiceConfig?,
  base_dir : String?,
) -> Result[Unit, String] {
  match service {
    None => Ok(())
    Some(service) => install_app_service_config(app, service, base_dir)
  }
}

///|
fn install_app_service_config(
  app : @wvrt.App,
  service : AppServiceConfig,
  base_dir : String?,
) -> Result[Unit, String] {
  match validate_app_service_config(service) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  install_valid_app_service_config(app, service, base_dir)
  Ok(())
}

///|
fn validate_app_service_config(
  service : AppServiceConfig,
) -> Result[Unit, String] {
  guard service.command().trim().to_owned() != "" else {
    return Err("app service command must not be empty")
  }
  guard service.op_names().length() > 0 else {
    return Err("app service must expose at least one op")
  }
  for op_name in service.op_names() {
    guard op_name.trim().to_owned() != "" else {
      return Err("app service op name must not be empty")
    }
  }
  Ok(())
}

///|
fn install_valid_app_service_config(
  app : @wvrt.App,
  service : AppServiceConfig,
  base_dir : String?,
) -> Unit {
  match service.cwd() {
    Some(cwd) =>
      app.install_service(
        service.command(),
        service.op_names(),
        args=service.args(),
        cwd~,
        extensions=service.extensions(),
      )
    None =>
      match base_dir {
        Some(cwd) =>
          app.install_service(
            service.command(),
            service.op_names(),
            args=service.args(),
            cwd~,
            extensions=service.extensions(),
          )
        None =>
          app.install_service(
            service.command(),
            service.op_names(),
            args=service.args(),
            extensions=service.extensions(),
          )
      }
  }
}

///|
/// Builds and installs every prepared extension into the runtime app.
fn install_prepared_extensions(
  app : @wvrt.App,
  prepared_extensions : Array[PreparedExtension],
  base_dir : String?,
) -> Result[Unit, String] {
  for prepared_extension in prepared_extensions {
    match install_prepared_extension(app, prepared_extension, base_dir) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
/// Builds and installs one prepared extension spec across the runtime app.
fn install_prepared_extension(
  app : @wvrt.App,
  prepared_extension : PreparedExtension,
  base_dir : String?,
) -> Result[Unit, String] {
  let prepared_id = prepared_extension.id()
  let context = @core.ExtensionBuildContext::new(
    options=prepared_extension.options(),
    base_dir~,
  )
  match app.install_extension_spec(prepared_extension.spec(), context) {
    Ok(_) => Ok(())
    Err(error) =>
      return Err("failed to build extension " + prepared_id + ": " + error)
  }
}

///|
/// Installs one optional prepared MBT process backend into the runtime app.
fn install_prepared_mbt_backend(
  app : @wvrt.App,
  backend : MbtProcessBackendConfig?,
  base_dir : String?,
) -> Result[Unit, String] {
  match backend {
    None => Ok(())
    Some(backend) => install_mbt_process_backend_config(app, backend, base_dir)
  }
}

///|
fn install_mbt_process_backend_config(
  app : @wvrt.App,
  backend : MbtProcessBackendConfig,
  base_dir : String?,
) -> Result[Unit, String] {
  match validate_mbt_process_backend_config(backend) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  install_valid_mbt_process_backend_config(app, backend, base_dir)
  Ok(())
}

///|
fn validate_mbt_process_backend_config(
  backend : MbtProcessBackendConfig,
) -> Result[Unit, String] {
  guard backend.command().trim().to_owned() != "" else {
    return Err("MBT process backend command must not be empty")
  }
  guard backend.op_names().length() > 0 else {
    return Err("MBT process backend must expose at least one op")
  }
  for op_name in backend.op_names() {
    guard op_name.trim().to_owned() != "" else {
      return Err("MBT process backend op name must not be empty")
    }
  }
  Ok(())
}

///|
fn install_valid_mbt_process_backend_config(
  app : @wvrt.App,
  backend : MbtProcessBackendConfig,
  base_dir : String?,
) -> Unit {
  match backend.cwd() {
    Some(cwd) =>
      app.install_mbt_process_backend(
        backend.command(),
        backend.op_names(),
        args=backend.args(),
        cwd~,
        extensions=backend.extensions(),
      )
    None =>
      match base_dir {
        Some(cwd) =>
          app.install_mbt_process_backend(
            backend.command(),
            backend.op_names(),
            args=backend.args(),
            cwd~,
            extensions=backend.extensions(),
          )
        None =>
          app.install_mbt_process_backend(
            backend.command(),
            backend.op_names(),
            args=backend.args(),
            extensions=backend.extensions(),
          )
      }
  }
}
