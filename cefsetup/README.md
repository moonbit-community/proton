# proton_cefsetup

`proton_cefsetup` installs the immutable CEF runtime required by a specific
Proton release and its matching subprocess executable. Runtime installations
are shared by all projects for a user and are selected by platform, archive
digest, and layout version. Subprocess executables are shared by platform and
Proton version under `~/.proton/subprocesses`.

Since 0.7.0, Proton CLI prepares this installation automatically for `dev`,
`build`, and `package`. Use `proton_cli setup` for optional prewarming from any
directory. Direct Moon builds still require prior setup.

Install the selected runtime and subprocess executable without the CLI with:

```sh
moonx moonbit-community/proton_cefsetup
```

Subprocess resolution rejects empty files and, on Unix, files without executable
permission. Setup repairs invalid cached executables under the installation lock;
these filesystem checks do not validate every possible binary corruption.
