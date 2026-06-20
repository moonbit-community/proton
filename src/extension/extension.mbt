///|
priv enum ExtensionKind {
  Framework(@core.ExtensionSpec)
  Command(@lepus_command.AppCommandExtensionSpec)
}

///|
struct Extension {
  kind : ExtensionKind
}

///|
struct Extensions {
  items : Array[Extension]
}

///|
pub fn from_core_spec(spec : @core.ExtensionSpec) -> Extension {
  Extension::{ kind: Framework(spec) }
}

///|
pub fn from_command_spec(
  spec : @lepus_command.AppCommandExtensionSpec,
) -> Extension {
  Extension::{ kind: Command(spec) }
}

///|
pub fn Extensions::new(items : Array[Extension]) -> Extensions {
  Extensions::{ items: copy_extensions(items) }
}

///|
pub fn extensions(items : Array[Extension]) -> Extensions {
  Extensions::new(items)
}

///|
pub fn Extension::id(self : Extension) -> String {
  match self.kind {
    Framework(spec) => spec.id()
    Command(spec) => spec.id()
  }
}

///|
pub fn Extension::core_spec(self : Extension) -> @core.ExtensionSpec? {
  match self.kind {
    Framework(spec) => Some(spec)
    Command(_) => None
  }
}

///|
pub fn Extension::command_spec(
  self : Extension,
) -> @lepus_command.AppCommandExtensionSpec? {
  match self.kind {
    Framework(_) => None
    Command(spec) => Some(spec)
  }
}

///|
pub fn Extensions::items(self : Extensions) -> Array[Extension] {
  copy_extensions(self.items)
}

///|
fn copy_extensions(items : Array[Extension]) -> Array[Extension] {
  items.map(fn(item) { item })
}
