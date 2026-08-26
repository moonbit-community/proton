///|
test "application descriptors preserve typed stable names" {
  let ping : Command[String, Int] = command("ping")
  let changed : Event[Int] = event("changed")
  assert_eq(ping.name(), "ping")
  assert_eq(ping.contract_route().operation_name(), "app:ping")
  assert_true(ping.contract_route().is_application())
  assert_eq(changed.name(), "changed")
  assert_eq(changed.contract_route().operation_name(), "app:changed")
}

///|
test "extension descriptors share an opaque extension route" {
  let ext = extension(
    id="moonbit-community/proton-dialog",
    js_namespace="dialog",
  )
  let open_file : Command[String, String] = ext.command("open_file")
  let selected : Event[String] = ext.event("selected")
  assert_eq(ext.id(), "moonbit-community/proton-dialog")
  assert_eq(ext.js_namespace(), "dialog")
  assert_false(open_file.contract_route().is_application())
  assert_eq(
    open_file.contract_route().extension_id(),
    Some("moonbit-community/proton-dialog"),
  )
  assert_eq(selected.contract_route().extension_namespace(), Some("dialog"))
  assert_eq(open_file.contract_route().operation_name(), "ext:dialog/open_file")
}

///|
test "descriptor validation reports empty application names" {
  let invalid : Command[Unit, Unit] = command(" ")
  invalid.validate() catch {
    ContractDefinitionError::EmptyApplicationName => ()
    _ => abort("expected EmptyApplicationName")
  }
}

///|
test "descriptor validation reports empty extension members" {
  let ext = extension(id="example/ext", js_namespace="example")
  let invalid : Event[Unit] = ext.event("")
  invalid.validate() catch {
    ContractDefinitionError::EmptyExtensionMember(extension_namespace="example") =>
      ()
    _ => abort("expected EmptyExtensionMember")
  }
}

///|
test "event validation rejects duplicate route declarations" {
  let first : Event[Int] = event("duplicate_event_route")
  let duplicate : Event[String] = event("duplicate_event_route")
  first.validate()
  first.validate()
  duplicate.validate() catch {
    ContractDefinitionError::DuplicateEventRoute(
      route="app:duplicate_event_route"
    ) => ()
    _ => abort("expected DuplicateEventRoute")
  }
}

///|
test "extension identity validation rejects empty fields" {
  let invalid_id = extension(id="", js_namespace="example")
  invalid_id.validate() catch {
    ContractDefinitionError::EmptyExtensionId => ()
    _ => abort("expected EmptyExtensionId")
  }
  let invalid_namespace = extension(id="example/ext", js_namespace="")
  invalid_namespace.validate() catch {
    ContractDefinitionError::EmptyExtensionNamespace => ()
    _ => abort("expected EmptyExtensionNamespace")
  }
}

///|
test "expected extension event error reports its route" {
  assert_eq(
    ContractDefinitionError::ExpectedExtensionEvent(route="app:changed").message(),
    "event route does not belong to an extension: app:changed",
  )
}
