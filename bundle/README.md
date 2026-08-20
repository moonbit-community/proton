# proton_bundle

`proton_bundle` adapts an already-built Proton application to the generic
`proton_package` library. It resolves Proton's immutable CEF runtime, stages the
matching `cef_process` executable, writes Proton metadata, and describes the
platform-specific signing layout.

The module does not inspect a MoonBit project or run a build. Callers provide a
complete `proton_package.PackageSpec`, the matching helper executable, and only
the additional Proton payload inputs. `build` returns both the produced
artifacts and the platform of the resolved runtime so callers do not need to
query the CEF store independently.
