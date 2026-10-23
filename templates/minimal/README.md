# Proton App

A minimal Proton desktop app.

Create this template with `proton_cli new my-app --template minimal`,
or invoke `moon-new` directly:

```sh
moonx moonbit-community/moon-new my-app \
  --template moonbit-community/proton --branch main \
  --subdir templates/minimal
```

Direct invocation uses `--user <name>` instead of `--author <name>`.

The application is a single MoonBit module. Its native entry point and inline
HTML live in `app/main.mbt`; no separate frontend toolchain is required.
The app calls `@proton.load_config()` to load its configuration from
`proton.project.json` during development and packaged metadata after release,
and installs it with `..config(@proton.load_config())`.

## Customize

Set a unique `identifier` and your `package.product_name` in `proton.project.json`
before distribution. Change the window title and dimensions in `app/main.mbt`;
update frontend titles where applicable. The initial values are `Proton App`,
960 × 640 and `com.example.proton-app`.

## Setup

```sh
moon update
proton_cli cef setup
```

## Check

```sh
moon check --target native --diagnostic-limit 80
```

## Dev

```sh
proton_cli dev
```

## Build

```sh
proton_cli build
```

## Package

```sh
proton_cli package --dry-run
proton_cli package --release
```
