# proton_cefsetup

`proton_cefsetup` installs the immutable CEF runtime required by a specific
Proton release. Runtime installations are shared by all projects for a user and
are selected by platform, archive digest, and layout version.

Install the selected runtime with:

```sh
moonx moonbit-community/proton_cefsetup
```

Proton's developer tools and bundler use the module's `store` package to resolve
and validate the installation without persisting project-local absolute paths.
