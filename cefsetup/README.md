# proton_cefsetup

`proton_cefsetup` installs the immutable CEF runtime required by a specific
Proton release and its matching subprocess helper. Runtime installations
are shared by all projects for a user and are selected by platform, archive
digest, and layout version. Helpers are shared by platform and Proton version
under `~/.proton/helpers`.

Install the selected runtime and helper with:

```sh
moonx moonbit-community/proton_cefsetup
```

Proton's developer tools and bundler use the module's `store` package to resolve
and validate the installation without persisting project-local absolute paths.
`setup_default` installs the complete release requirement. Consumers resolve
the immutable runtime and helper paths without rebuilding either artifact.
Runtime and helper installation each use a lock and adjacent staging directory
before publishing their final versioned directory.
