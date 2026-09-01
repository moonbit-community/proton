# Application Protocol And Process Control

Manual review for Electron-style default protocol client registration,
immediate process exit, and application relaunch.

Build the development form from the repository root:

```sh
PROTON_NO_UPDATE_CHECK=1 moon -C cli run . -- dev -C .. \
  --config examples/75_app_protocol_process/proton.project.json
```

The development form can review relaunch and exit. On macOS, protocol
registration intentionally reports that a packaged application is required.

Build and run the packaged macOS application:

```sh
moon -C cli run . -- package -C .. \
  --config examples/75_app_protocol_process/proton.project.json \
  --format app
open "dist/Proton App Control.app"
```

1. Select **Refresh** and record the current default-handler state. macOS may
   already report `yes` after LaunchServices discovers the packaged bundle.
2. Select **Register**, refresh, and confirm the state is `yes`.
3. Open `proton-control-review://manual-review` and confirm the packaged app is
   activated.
4. Select **Remove** and refresh. If another handler exists, confirm the state
   becomes `no`; otherwise LaunchServices may rediscover this bundle as the
   only available handler. This deliberately changes the system default, so
   perform it only when protocol cleanup is part of the review.
5. Select **Relaunch + quit**. A new instance must open with
   `--proton-relaunch-review` in Startup argv after orderly shutdown.
6. Select **Relaunch + exit**. A new instance must still open, while close
   interception and lifecycle shutdown are skipped in the old process.
7. Run the development executable from a terminal and select **Exit code 7**;
   confirm the process exits with status 7 and no replacement instance opens.

On Windows, also inspect
`HKCU\\Software\\Classes\\proton-control-review` after register/remove. On
Linux, install or integrate the generated `.desktop` entry before registration;
Electron does not expose protocol removal on Linux, so **Remove** returns false.
