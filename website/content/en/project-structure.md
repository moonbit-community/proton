# Project structure

[中文](zh/project-structure.html)

A Proton project contains application code, MoonBit package metadata, and CLI configuration. The templates differ in frontend organization, not in the native runtime they use.

## The minimal project

```text
hello-proton/
  moon.mod
  proton.project.json
  app/
    moon.pkg
    main.mbt
```

- **`moon.mod`** gives the module its name and declares versioned dependencies. Add a library here before importing its packages.
- **`app/moon.pkg`** imports the packages used by the entry and marks it as a native executable.
- **`app/main.mbt`** defines the async entry, HTML, and application builder.
- **`proton.project.json`** tells the CLI which package to run and how to identify/package the app.

Adding a module dependency does not automatically import it into every package. For example, the [command guide](commands-events.md) adds both a `proton_contract` module dependency and a package import.

## The isomorphic project

Create a separate project with `--template isomorphic` when you want a MoonBit frontend:

```text
todo-app/
  moon.work
  proton.project.json
  shared/
    moon.mod
    moon.pkg
    todo_contract.mbt
  backend/
    moon.mod
    app/
      moon.pkg
      main.mbt
    todo/
      moon.pkg
      backend.mbt
      commands.mbt
  frontend/
    moon.mod
    main/
      moon.pkg
      main.mbt
    internal/query/
    public/
```

The root `moon.work` connects three modules:

- **shared** defines serializable payloads and command/event descriptors. It is used by both build targets.
- **backend** builds to native code. `todo/backend.mbt` holds Todo state and operations; `todo/commands.mbt` binds those operations; `app/main.mbt` starts the app.
- **frontend** builds to JavaScript. `main/main.mbt` defines the Rabbita UI; `public/` contains its HTML and stylesheet.

The template's `frontend/internal/query` manages query state and subscriptions. It belongs to the generated application and can be changed with it; it is not a public Proton API.

## Configuration boundaries

Use Moon module/package files for dependencies and imports. Use `proton.project.json` for backend/frontend build paths and package metadata. Use the MoonBit app builder for windows, commands, capabilities, and lifecycle hooks.

Application command bindings are ordinary code. You do not need to add a command code-generation rule to the isomorphic template.

## Generated output

Moon writes build output under `_build/` and resolved dependencies under `.mooncakes/`. Warren writes the frontend build under `frontend/dist/`; the packager writes distributables under the configured output directory, normally root `dist/`.

Do not edit these outputs. Edit the source or project configuration and rebuild. The runtime and helper installed by setup are shared user-level files, not project source.

Continue with [architecture and processes](architecture.md), or follow the [Todo tutorial](isomorphic.md) to modify a complete application.
