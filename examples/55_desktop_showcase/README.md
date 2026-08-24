# Proton Desktop Showcase

Run the source example from the repository root:

```sh
moon -C examples run 55_desktop_showcase --target native
```

On macOS, system notifications require an application bundle with a bundle
identifier. Build the presentation-ready `.app` from the repository root:

```sh
moon -C cli run . -- package \
  -C .. \
  --config examples/55_desktop_showcase/proton.project.json \
  --format app
```

The packaged application is written to `dist/Proton Desktop Showcase.app`.
