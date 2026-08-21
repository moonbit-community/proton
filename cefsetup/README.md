# proton_cefsetup

`proton_cefsetup` installs the immutable CEF runtime required by a specific
Proton release and its matching subprocess helper. Runtime installations
are shared by all projects for a user and are selected by platform, archive
digest, and layout version. Helpers are shared by platform and Proton version
under `~/.proton/helpers`.

Install the selected runtime with:

```sh
moonx moonbit-community/proton_cefsetup
```

Proton's developer tools and bundler use the module's `store` package to resolve
and validate the installation without persisting project-local absolute paths.
The package exposes default-runtime operations for direct use and declared-
runtime operations for tooling that must follow an application's resolved
Proton dependency. Both return the resolved SDK, runtime, platform, and archive
paths. Installation uses one lock and one staging directory before atomically
publishing a manifest-backed runtime.
