# Creating a Proton project

`proton_cli new` creates a native-first MoonBit desktop application with a
runnable `app` package, a reusable counter command extension, project runtime
configuration, and package-ready bundle metadata.

## Create the project

Install the CLI, then create the project before setting up its native runtime:

```sh
moon install justjavac/proton_cli
proton_cli new my-counter \
  --title "My Counter" \
  --identifier "com.example.my-counter"
cd my-counter
proton_cli cef setup
```

The application identifier must use reverse-DNS form. If `--identifier` is
omitted, Proton derives `dev.proton.<project-name>`, replacing `_` and `.` in
the project name with `-`.

Useful creation options:

- `--title <title>` sets the product and initial window title.
- `--module <name>` sets the `moon.mod` module name.
- `--identifier <id>` sets the application bundle identifier.
- `--width <px>` and `--height <px>` set the initial window size.
- `--no-check` skips the native `moon check` run after file creation.
- `--git` initializes a Git repository; `--no-git` explicitly disables it.
- `-y` or `--yes` accepts defaults and disables interactive prompts.
- `--dry-run` prints the file plan without writing the project.

By default, `new` runs:

```sh
moon check --target native --diagnostic-limit 80
```

This check resolves the registry versions recorded in the generated
`moon.mod`. Use `--no-check` only for offline scaffolding or when dependency
resolution will be performed later.

## Generated layout

```text
my-counter/
├── app/
│   ├── app.html
│   ├── main.mbt
│   └── moon.pkg
├── extensions/
│   └── counter/
│       ├── counter.mbt
│       ├── moon.pkg
│       └── README.mbt.md
├── AGENTS.md
├── README.mbt.md
├── LICENSE
├── moon.mod
└── moon.proton
```

- `app/` is the only runnable application package.
- `extensions/counter/` exposes the example command bridge extension used by
  the app; it is not a standalone executable.
- `moon.proton` owns the application identifier, window, entry, development,
  and packaging configuration.
- `.proton/` is created later by `proton_cli cef setup` and must not be
  committed.

## Develop and build

Run these commands from the generated project root:

```sh
proton_cli dev
proton_cli build
```

`dev` runs the `app` package with the setup-managed runtime. `build` performs
the release frontend step when configured and builds `app` for the native
target.

## Package

The generated `moon.proton` is package-ready by default:

```moonbit
bundle = {
  active: true,
  targets: ["app", "zip"],
  output: "target/proton-dist",
}
```

Inspect the resolved plan before creating artifacts:

```sh
proton_cli package app --dry-run
proton_cli package app
```

The real package command requires the active runtime created by
`proton_cli cef setup`. Output is written to `target/proton-dist` unless
`bundle.output` or `--output` overrides it.

See [Packaging and signing](packaging.md) for icons, resources, platform
layouts, signing, notarization, and Windows Authenticode configuration.

## Frontend projects

For Vite, Next, or another frontend toolchain, add a `frontend` block to
`moon.proton` and point the production `entry` at the generated frontend file.
`proton_cli dev` owns the development server lifecycle, while `build` and
`package` run `frontend.before_build` and validate `frontend.dist`.

The repository's root [README](../README.md) contains a complete frontend
configuration example.
