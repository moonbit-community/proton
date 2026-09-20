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
