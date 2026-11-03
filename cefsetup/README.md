# proton_cefsetup

`proton_cefsetup` installs the immutable CEF runtime required by a specific
Proton release and its matching subprocess helper. Runtime installations
are shared by all projects for a user and are selected by platform, archive
digest, and layout version. Helpers are shared by platform and Proton version
under `~/.proton/helpers`.

The unreleased Proton CLI prepares this installation automatically for `dev`,
`build`, and `package`. Use `proton_cli setup` for optional prewarming from any
directory. Direct Moon builds still require prior setup.

Install the selected runtime and helper without the CLI with:

```sh
moonx moonbit-community/proton_cefsetup
```

Helper resolution rejects empty files and, on Unix, files without executable
permission. Setup repairs invalid cached helpers under the installation lock;
these filesystem checks do not validate every possible binary corruption.
