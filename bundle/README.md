# proton_bundle

`proton_bundle` adapts an already-built Proton application to the generic
`proton_package` library. It resolves Proton's immutable CEF runtime, stages the
matching `cef_process` executable, writes Proton metadata, and describes the
platform-specific signing layout.

The module does not inspect a MoonBit project or run a build. Callers provide
the application executable, the matching helper executable, package metadata,
and project payload paths explicitly.
